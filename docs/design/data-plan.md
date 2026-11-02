# Plan de la couche données — cache, sync, resolver, images

Statut : proposition, à valider par Antonin avant le premier commit de code de la couche données (et avant le lot 3.1
du plan UI).
Périmètre : tvOS 17+, Swift 6, `Packages/JellyKit` (cibles `LibraryKit`, futur `PlaybackEngine`), SDK `jellyfin-sdk-swift`.
Ce document consomme `docs/design/ui-plan.md` (§4.3, §9, §10, §11) et le complète ; il ne touche ni au player ni à l'UI.

Sources lues pour l'écrire (lecture seule) :

- App RN archivée, `~/projects/jellyfuse` : `CLAUDE.md` (« Data Flow »), `packages/query-keys/src/index.ts`,
  `apps/mobile/src/services/{query,playback,connection,settings,auth,api}`, `packages/api/src/{playback,shelves,detail}.ts`,
  hooks de `services/query/hooks/`, `features/player/hooks/use-reporting-session.ts`, commits PR #24 (`24c601c`) et #25 (`52b8cbf`).
  Les chemins ci-dessous sont relatifs à `apps/mobile/src/` pour `services/…` et `features/…`, sinon à la racine du dépôt RN.
- Sillon, `~/projects/sillon` : `LibraryKit/{JellyfinClient,SessionStore,Network/ServerReachability,Store/LibraryChangedListener,Listens/ListenSync,Suggestions/SuggestionsSnapshot,Images/ImageCache}`.
- SDK Swift (checkout dans `.build`) : `JellyfinSocket`, `OutboundWebSocketMessage`, `PlaybackStateInfo`, `DeviceProfile`, `UserItemDataDto`, `LibraryUpdateInfo`.
- Code serveur Jellyfin : `UserDataManager.UpdatePlayState` (lu sur GitHub `master` pendant cette session).
- Mémoire projet et `docs/lessons-learned.md` pour les décisions actées.

Les règles citent leur source entre crochets : `[RN: fichier]`, `[mémoire: nom]`, `[sillon: fichier]`, `[SDK: fichier]`,
`[serveur: fichier]`. Une règle sans source est une décision nouvelle de ce plan et est marquée **(nouveau)**.

---

## 0. Résumé des décisions

| # | Décision | Reco |
|---|---|---|
| D1 | Pas de port de TanStack Query ni de framework de cache générique. Un `LibraryStore` `@MainActor @Observable` par session, des loaders typés, une table `Staleness` en code. | ferme |
| D2 | **Normaliser `UserData`** : les listes stockent des identifiants, la progression/vu/favori vit dans un seul dictionnaire. Supprime l'équivalent de `isAffectedQuery` + `patchCache` (la partie la plus coûteuse du RN). | ferme |
| D3 | Persistance disque = snapshots JSON Codable dans `Caches/`, par propriétaire (serveur+user), versionnés, hydratés « périmés ». Pas de SwiftData pour le cache. | ferme, sous réserve du spike stockage tvOS (§3.4) |
| D4 | File de reports de lecture = acteur séparé, journal d'événements coalescés, une entrée ne sort qu'après acceptation serveur (pattern `ListenSync` de sillon), drain arrêté au premier échec. Corrige deux défauts du RN (§5.3). | ferme |
| D5 | Websocket du SDK (`JellyfinSocket`) : `UserDataChanged` applique les `UserItemDataDto` reçus directement (zéro refetch d'item) ; `LibraryChanged` marque périmées les shelves « récents ». Le RN n'avait **aucun** websocket (§5.5). | ferme |
| D6 | Resolver et device profile dans `PlaybackEngine`, purs et testés ; profil tvOS = profil RN permissif, avec la même table de codecs et les strings canoniques. | ferme |
| D7 | Images : Nuke, URLs construites avec le `tag`, tailles de `ui-plan §9.3`. | ferme |
| D8 | Phase 2 : ce qui est en place (`JellyfinClient`, `SessionStore`) reste ; on lui ajoute la plomberie (reachability, 401 → `onUnauthorized`, protocole d'abstraction pour tests) avant les ressources. | ferme |

Hors v1 et supprimé de la transposition : Jellyseerr (requêtes, progression Radarr/Sonarr, qualités, TMDB), téléchargements
locaux, recherche mixte. `[ui-plan §13]`, `[mémoire: reboot Apple TV]`.

---

## 1. Ce que le RN a appris (les règles métier, indépendamment de TanStack)

`CLAUDE.md` du RN énonce 9 règles. Ce plan leur donne à chacune un équivalent explicite (tableau §2). Mais le savoir
réel se trouve davantage dans le code que dans ces 9 lignes ; voici ce qui y est enfoui et que le Swift doit reprendre.

1. **Stale-while-revalidate partout.** Tout s'affiche depuis le cache, la revalidation est silencieuse. `[RN: services/query/README.md « Hydrate-as-stale »]`
2. **Hydratation = périmé.** Au boot, toute entrée rechargée du disque est marquée `dataUpdatedAt: 0` : rendu immédiat, refetch au montage. `[RN: services/query/provider.tsx onSuccess]`
3. **Allowlist de persistance, défaut = non.** Seuls `home`, `detail`, `shelf`, `system-info`, `quality-profiles` sont écrits sur disque ; une clé inconnue n'est pas persistée ; seules les requêtes en `success` le sont. `[RN: services/query/should-dehydrate.ts]`
4. **Version de schéma = « buster ».** Un changement de forme d'un modèle persisté jette tout le cache au lieu de migrer (le cache est jetable). Âge max 30 jours. `[RN: services/query/schema.ts]`
5. **Le cache est la liste des endroits où un même item vit.** Un même `MediaItem` est dupliqué dans 5 familles de requêtes ; marquer « vu » oblige à le patcher partout, via un prédicat (`isAffectedQuery`) et un `patchCache` qui reconnaît 4 formes de données. C'est la plus grosse source de complexité du RN. `[RN: services/query/hooks/played-cache-patch.ts]`
6. **Patch optimiste = règles du serveur répliquées.** Marquer vu : `played=true`, `playCount>=1`, `lastPlayedDate=now`, position **conservée** ; marquer non vu : tout remis à zéro y compris la position. Sur la série parente, seul `lastPlayedDate` est touché, le reste attend le refetch. `[RN: played-cache-patch.ts patchMediaItemPlayed]`
7. **Mutations optimistes : annuler les refetch en vol avant de patcher**, snapshot, rollback sur erreur. `[RN: use-played-state.ts onMutate/onError]`
8. **Un arrêt de lecture ne doit pas écraser la position serveur.** Pas de report `Stopped` si mpv n'a jamais émis de progression (sinon `PositionTicks: 0` remet à zéro le point de reprise et « Reprendre » saute à l'épisode suivant). `[RN: features/player/hooks/use-reporting-session.ts, commentaire sur sawProgressRef]`
9. **Le serveur persiste le choix audio/sous-titres sur `UserItemData`** via les reports Progress (pas Stopped : `PlaybackStopInfo` n'a pas ces champs) et le renvoie en `MediaSource.Default*StreamIndex` ; `-1` = « pas de sous-titre ». Le client envoie toujours, le serveur filtre selon `RememberAudio/SubtitleSelections`. `[RN: reporter.ts en-tête ; commit 24c601c]`
10. **`DefaultAudioStreamIndex` serveur n'est pas un choix utilisateur** : il peut n'être que le `IsDefault` du fichier. D'où la priorité locale > serveur (§5.4). `[RN: resolver.ts commentaire « Priority chain » ; commit 24c601c]`
11. **Le ping `/System/Info/Public` fait office de test de joignabilité** (5 s, toutes les 30 s, sans retry, le pas de l'intervalle est le retry), combiné au signal OS « pas de réseau ». Et il porte le même `staleTime` (1 h) que la ressource. `[RN: services/connection/monitor.ts]`
12. **Les reports tentent d'abord le réseau sauf si le serveur est déjà connu hors ligne**, auquel cas ils vont directement en file. `[RN: reporter.ts isKnownOffline]`
13. **Les URL de flux portent `api_key`** : mpv ne peut pas envoyer d'en-têtes. `[RN: packages/api/src/playback.ts parsePlaybackInfo]`
14. **Le profil d'appareil est un paramètre** et doit avoir des `CodecProfiles`, sinon Jellyfin retombe silencieusement en transcodage sur du 10 bits/HDR/Dolby Vision sans `TranscodeReasons`. `[RN: playback.ts buildDeviceProfile, commentaire CodecProfiles]`
15. **Un changement de plafond de débit invalide tous les `PlaybackInfo` en cache.** `[RN: features/settings/screens/settings-screen.tsx:118]`

Défauts du RN à ne pas reproduire (constatés en lisant le code, détail en §5.3) :

- Le reporter passe `itemId: resolved.mediaSourceId` à la place de l'id de l'item `[RN: use-reporting-session.ts doReportStart/Progress/Stopped]` : identique sur une seule version, faux sur un item à plusieurs versions.
- Le drain de la file **vide d'abord puis rejoue** (`drainReports()` supprime les entrées avant envoi) et le rejeu passe par `sendReport`, qui **ré-enfile en cas d'échec sans jamais lever** : le `catch { enqueueReport; break }` de `use-report-drainer.ts` n'est donc jamais atteint, le drain martèle un serveur en récupération, et un crash en cours de drain perd les entrées.
- `useTogglePlayedState` invalide dans `onSettled` donc **aussi en cas d'erreur**, contre la règle actée « invalidation seulement sur succès » `[mémoire: optimistic patch + invalidation]` (le commentaire du hook dit l'inverse du code).
- Pendant une coupure, chaque progression (toutes les 5 s) est mise en file (plafond 500) alors que seule la dernière compte.

---

## 2. Architecture du store Swift

### 2.1 Options considérées

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| A. Port d'un « QueryClient » (clés, observers, gc, retry, dédoublonnage génériques) | Fidélité au RN | C'est le framework maison que le plan de reboot interdit ; coût énorme pour 12 ressources ; SwiftUI n'a pas besoin d'observers manuels | rejeté `[ui-plan §4.3 « pas de store maison généralisé »]` |
| B. Un repository `actor` par domaine, caches TTL internes, `AsyncStream` d'updates, vues via `@Observable` | Isolation d'acteur propre | Les vues ont besoin de lectures **synchrones** pour le premier rendu depuis le cache ; chaque repository doit republier ses données ; le patch optimiste doit traverser plusieurs repositories (retombe dans le problème n°5 du RN) | rejeté comme structure principale |
| C. SwiftData comme store (sillon `LibraryStore`) | Requêtes, persistance incluse | Sillon miroite toute une bibliothèque musicale hors ligne ; ici ce sont des shelves ordonnés par le serveur ; tvOS ne garantit pas un stockage persistant (§3.4) ; coût de migration de schéma | rejeté pour le cache |
| **D. Un `LibraryStore` `@MainActor @Observable` normalisé, loaders typés, snapshots JSON** | Lectures synchrones, patch optimiste en un point, vues minces, aucune dépendance, conforme à `AppModel` de sillon | Une classe qui grossit (mitigé : un fichier d'extension par domaine) | **retenu** |

Les opérations réseau restent dans l'acteur `JellyfinClient` (déjà en place) ; le store, isolé au `@MainActor`, ne bloque
pas l'interface car il `await` l'acteur. Les files de reports et le websocket vivent dans des acteurs à part (ils n'ont
rien à faire sur le thread principal).

### 2.2 Les composants

```
JellyfinClient (actor)            E/S HTTP seulement, SDK. Existe.
   ▲
LibraryStore (@MainActor @Observable), un par Session
   ├─ items:      [ItemID: MediaItem]         métadonnées quasi immuables (nom, tags d'image, ids parents…)
   ├─ userData:   [ItemID: UserData]          vu / position / favori / playCount  ← source unique (D2)
   ├─ shelves:    [ShelfKey: Stamped<[ItemID]>]   ordre serveur, ids seulement
   ├─ details:    [ItemID: Stamped<ItemDetail>]
   ├─ children:   [ItemID: Stamped<[ItemID]>]     saisons d'une série, épisodes d'une saison
   ├─ config:     Stamped<UserConfiguration>
   ├─ inflight:   [ResourceKey: Task<Void, Never>]   dédoublonnage
   └─ load(_:force:), ensureFresh(_:), patch…, invalidate…
PlaybackReporter (actor)  +  ReportJournal (fichier)   §5.1-5.3
ServerEvents (actor)      consomme JellyfinSocket, appelle le store   §5.5
SnapshotStore             lit/écrit les snapshots JSON dans Caches   §3
ServerReachability        @MainActor @Observable, copié de sillon     §4
```

Principes :

- **`Stamped<Value>`** = `(value, fetchedAt: Date)`. Un snapshot rechargé du disque est installé avec `fetchedAt = .distantPast`
  (équivalent de `dataUpdatedAt: 0`). `isStale(now) = now - fetchedAt > Staleness.interval(for: key)`.
  `[RN: provider.tsx]`
- **`Staleness`** : un seul fichier, une `enum ResourceKind` avec `var staleTime: Duration` (tableau §3.1). Aucune valeur
  en dur dans un écran, comme `STALE_TIMES` du RN. `[RN: packages/query-keys/src/index.ts]`
- **Lecture** : une vue lit `store.shelf(.continueWatching)` (synchrone, depuis la mémoire), et son `XxxModel` appelle
  `await store.ensureFresh(.continueWatching)` au `.task` de l'écran. `ensureFresh` ne fait rien si la donnée est fraîche,
  lance le fetch sinon, et dédoublonne via `inflight`. C'est le `staleTime` + refetch-au-montage de RQ.
- **Jointure à la lecture** : le modèle d'affichage d'une carte = `items[id]` ⨝ `userData[id]`. Un patch optimiste n'a donc
  qu'**un** endroit à modifier (D2). Une fiche détaillée porte son propre `UserData` initial mais le store le recopie dans
  `userData` à l'écriture, jamais l'inverse.
- **Portée** : le `LibraryStore` est construit pour une `Session`. Changer d'utilisateur = jeter l'instance (équivalent de
  `queryClient.clear()`, règle 7 du RN). Pas de `userId` dans les clés puisque le store est déjà par utilisateur.
- **Annulation avant patch** : avant un patch optimiste, on annule les tâches `inflight` des ressources affectées, sinon un
  fetch en vol écraserait le patch. `[RN: use-played-state.ts cancelQueries]`
- **`retry`** : les GET idempotents réessayent 2 fois (1 s puis 2 s) sur erreur réseau seulement, jamais sur 4xx ; les
  mutations 0 fois (la file de reports a sa propre logique). `PlaybackInfo` : 1 fois. `[RN: services/query/client.ts retry: 2, mutations retry: 0 ; use-playback-info.ts retry: 1]`
- **Pas de `gcTime`** : le RN gardait 24 h en mémoire ; ici la vie du store = la vie de la session, et un plafond simple
  (200 fiches détaillées, éviction du plus ancien) suffit. **(nouveau)**

### 2.3 Tableau de correspondance : les 9 règles RN → Swift

| # | Règle RN (`CLAUDE.md` « Data Flow ») | Équivalent Swift | Source / note |
|---|---|---|---|
| 1 | Clés de requête dans `packages/query-keys`, une entrée par ressource, avec `staleTime` | `enum ResourceKind` + `Staleness.swift` (§3.1), une seule table, aucun nombre en dur | `[RN: query-keys/src/index.ts]` |
| 2 | Appels HTTP purs dans `packages/api`, `ApiClient` injecté, sans état | `JellyfinClient` (actor, SDK) derrière un protocole `LibraryAPI` pour injecter un faux dans les tests | `[mémoire: façade actor]`, `[sillon: JellyfinClient]` |
| 3 | Hooks `useXxx` enveloppant chaque clé | `store.ensureFresh(_:)` + `store.<ressource>` lisibles depuis les `XxxModel` `@Observable` | `[ui-plan §4.3]` |
| 4 | Persistance MMKV, hydratation « périmé puis revalide » | `SnapshotStore` JSON dans `Caches/`, `fetchedAt = .distantPast` à l'hydratation, allowlist, `schemaVersion`, âge max 30 j (§3.3) | `[RN: persister.ts, schema.ts, should-dehydrate.ts]` |
| 5 | Optimiste : `setQueryData` d'abord, mutation, `onError` rollback | `store.mutate(…)` : annule inflight → snapshot de **l'entrée** `userData[id]` → patch → appel → rollback si erreur (§5.6) | `[RN: use-played-state.ts]`, `[mémoire: optimistic patch]` |
| 6 | Invalidation par prédicat (`invalidateQueries({predicate})`) | `store.markStale(_ kinds: Set<ResourceKind>)` : l'invalidation est un ensemble de **genres de ressource**, plus de prédicat sur des tableaux de clés. Seulement sur succès | `[RN: played-cache-patch.ts isAffectedQuery]`, `[mémoire: invalidation seulement sur succès]` |
| 7 | Changement d'utilisateur = `queryClient.clear()` | Instance de store jetée ; snapshots disque conservés **par propriétaire** pour la reprise rapide d'un profil, supprimés à la suppression du profil / déconnexion | `[RN: auth/state.tsx clearQueryCacheExceptAuth]` ; le disque par propriétaire est **(nouveau)** car le multi-profil est de premier rang sur Apple TV |
| 8 | Téléchargements locaux = seule exception, le module natif est la source de vérité | **Supprimée** : pas de téléchargements en v1 | `[ui-plan §13]` |
| 9 | Reports de lecture en attente dans une entrée MMKV dédiée, drainée à la reconnexion par `connection/monitor.ts` | `ReportJournal` + `PlaybackReporter` ; drain déclenché par `ServerReachability` (retour `online`) et au lancement (§5.3) | `[RN: pending-store.ts, use-report-drainer.ts, monitor.ts]` |

Règles RN implicites, hors des 9 :

| Mécanisme RN | Swift | Note |
|---|---|---|
| `refetchOnWindowFocus` / `refetchOnReconnect` | `scenePhase == .active` et passage `online` → `store.refreshVisible()` qui revalide les ressources périmées de l'écran courant | `[RN: client.ts]` |
| `onlineManager` branché sur `expo-network` : hors ligne = requêtes en pause (cache rendu sans erreur) | `ServerReachability` : hors ligne, `ensureFresh` ne lance rien et ne passe pas en échec ; le bandeau `Banner` suffit | `[RN: client.ts commentaire]`, `[sillon: ServerReachability]` |
| `refetchInterval` (progression Radarr, requêtes Jellyseerr) | Supprimé (Jellyseerr hors produit) | |
| `fetchQuery` du contexte d'auth (cache de `AuthContext`) | Inutile : la façade acteur détient déjà le jeton | `[RN: api/client.ts]` |
| Clé d'infini `shelfPage` (page de 50, `StartIndex`) | `store.page(of: ShelfKey)` : `[ItemID]` + `nextStartIndex`, tirée par la bibliothèque (lot 3.5) ; page 50 | `[RN: use-shelf-infinite.ts]` |

---

## 3. Inventaire des ressources

### 3.1 Table `Staleness` (valeurs du RN, sans invention)

Tous les temps viennent de `STALE_TIMES` `[RN: packages/query-keys/src/index.ts]` sauf mention. « RN persisté » vient de
`should-dehydrate.ts`. « Swift v1 » dit ce que le plan retient. Les ressources de Jellyseerr/Radarr/TMDB sont listées en
fin de tableau pour mémoire et **ne sont pas portées**.

| Ressource (clé RN) | staleTime RN | Scope RN | RN persisté | Invalidation observée dans le RN | Swift v1 |
|---|---|---|---|---|---|
| `systemInfo(baseUrl)` | 1 h ; ping toutes les 30 s, timeout 5 s, retry 0 `[monitor.ts]` | baseUrl | oui | — | Remplacé par `ServerReachability` (même ping), pas une ressource du store |
| `continueWatching(userId)` | 60 s | user | oui (`home`) | arrêt de lecture, vu/non vu, ajd. `UserDataChanged` (§5.5) | `ResourceKind.continueWatching` 60 s, persisté |
| `nextUp(userId)` | 60 s | user | oui | idem | 60 s, persisté |
| `seriesNextUp(userId, seriesId)` | 60 s (« tranche d'un élément de nextUp ») | user+série | oui (`detail`) | non (jamais invalidée, voir note 1) | 60 s, mémoire seule |
| `recentlyAdded(userId)` | 5 min | user | oui | arrêt de lecture, vu/non vu (le badge) | 5 min, persisté |
| `latestMovies(userId)` | 5 min | user | oui | idem | 5 min, persisté |
| `latestTv(userId)` | 5 min | user | oui | idem | 5 min, persisté |
| `suggestions(userId)` | 2 min (valeur héritée du Rust, **non réglée**) ; shelf « static » côté RN, jamais alimentée par Jellyfin `[RN: shelf-screen.tsx:94]` | user | oui | — | 2 min **par défaut hérité**, à régler quand `getSuggestions` sera branché (lot 3.2 « Reco ») |
| `requests(userId)` | 2 min + `refetchInterval` 15 s | user | oui | — | non porté |
| `shelfPage(userId, shelfKey)` | **aucun `staleTime`** (défaut 0, refetch à chaque montage), page de 50 `[use-shelf-infinite.ts]` | user+shelf | oui | arrêt de lecture, vu/non vu | 5 min pour les « récents », 60 s pour reprise/à suivre (même valeur que le shelf d'accueil correspondant, décision **(nouveau)** car le RN refetchait toujours) |
| `movieDetail(userId, id)` | 2 min | user+item | oui | arrêt de lecture, vu/non vu | 2 min, mémoire (voir D3 / Q3) |
| `seriesDetail(userId, id)` | 2 min | user+item | oui | idem | 2 min, mémoire |
| `seasonEpisodes(userId, seasonId)` | 5 min | user+saison | oui | idem | 5 min, mémoire |
| `adjacentEpisode(userId, series, episode)` | 5 min (`seasonEpisodes`) `[use-detail.ts:138]` | user+épisode | oui | — | 5 min, mémoire ; utilisé pour l'enchaînement d'épisodes (§5.4) |
| `seasonInfo(userId, tmdbId)` | 10 min | TMDB | oui | — | non porté (TMDB via Jellyseerr) |
| `playbackInfo(userId, itemId)` | **0**, gc 60 s, retry 1 `[use-playback-info.ts]` | user+item | **non** | changement du plafond de débit | **Pas une ressource du store** : appelée par `PlaybackEngine` à chaque lecture, jamais cachée |
| `introSkipper(itemId)` | 5 min (inline), gc 60 s, retry 0, « ne jamais échouer » | item | non | — | remplacé par `getItemSegments` (Jellyfin ≥ 10.10, `ui-plan §9.1`) ; 5 min, mémoire, absence ≠ erreur |
| `trickplayInfo(itemId)` | 5 min (inline), gc 60 s | item | non | — | Lu depuis `BaseItemDto.trickplay` ; pas de requête séparée (le RN relisait toute la fiche) |
| `userConfiguration(userId)` | 1 h ; invalidée explicitement à chaque `updateUserConfiguration` réussi | user | **non** (clé non listée → défaut non persisté) | mutation de config | 1 h, mémoire ; relue au lancement (valeur initiale des préférences de lecture) |
| `search(userId, query)` | 30 s | user+requête | **non** | — | 30 s, mémoire (lot 3.6) |
| `downloadProgress`, `downloadProgressMap` | 10 s + polling | TMDB / user | non | — | non porté (Radarr/Sonarr) |
| `qualityProfiles(service)` | 30 min | service | oui | — | non porté |
| `tmdbTvSeasons`, `tmdbDetail` | 5 min / 2 min | TMDB | oui (`detail`) | — | non porté |
| `jellyseerrRequests(userId)` | 2 min + 15 s | user | non | optimistic PR #25 | non porté |
| `localDownloads*` | n/a (module natif) | user | non | — | non porté |
| `pendingDownload(jellyfinId)` | transitoire | — | non | — | non porté |

Notes :

1. `seriesNextUp` n'est invalidée par aucun chemin dans le RN : le patch « vu » (`isAffectedQuery`) n'inclut ni cette
   famille (`detail/series-next-up`) ni `adjacent-episode`. Après avoir marqué un épisode vu, la cible « reprendre » d'une
   série peut donc rester périmée jusqu'à 60 s. Swift : ces deux ressources entrent dans l'ensemble invalidé par un arrêt de
   lecture ou un changement de vu (§5.6).
2. `STALE_TIMES.seasonInfo` (10 min) et la valeur `suggestions` (2 min) n'ont pas d'historique de réglage visible dans le
   dépôt ; seules les valeurs commentées « Rust : 60/120/300/1800 s » sont des constantes héritées de l'app Rust `jf-core`
   (`query.rs::stale_time()`), pas des résultats de mesure RN. À traiter comme point de départ, pas comme vérité.
3. Le RN ne renvoie jamais d'ID de série à `isAffectedQuery` : il patche « toute la famille » plutôt que de savoir quelles
   familles contiennent l'item. D2 supprime ce besoin.

### 3.2 Scopes

- Propriétaire (`Session.libraryOwner = "\(serverURL)|\(userId)"`, déjà défini) `[sillon: JellyfinClient.swift:15]` : tout
  le store, tous les snapshots disque, les préférences de pistes mémorisées, la file de reports.
- Pas de ressource scopée `serverId` seule : le seul cas RN (`systemInfo(baseUrl)`) devient `ServerReachability`.
- Les reports en file portent leur propriétaire ; on ne rejoue jamais un report sous un autre utilisateur.

### 3.3 Persistance : hydrate périmé puis revalide

- Un fichier JSON par propriétaire : `Caches/jellyfuse/<sha256(owner)>/home.json`, contenant `{ schemaVersion, savedAt, owner,
  views, shelves, items, userData }` pour les ressources de l'allowlist. `[sillon: SuggestionsSnapshot pour owner, save atomique, owner vérifié au chargement]`
- Allowlist explicite (enum), défaut = non. v1 : `views`, shelves d'accueil, et les `items`/`userData` qu'elles
  référencent. Les fiches détaillées ne sont **pas** persistées (Q3). `[RN: should-dehydrate.ts]`
- Écriture : après chaque mise à jour réussie d'une ressource persistée, avec une temporisation de 1 s (« throttleTime: 1000 »
  du persister RN) ; uniquement des états `loaded`. `[RN: persister.ts, should-dehydrate.ts « status success »]`
- Lecture : au lancement de la session, synchrone et petit (quelques dizaines de ko) ; version différente ou propriétaire
  différent ou âge > 30 j (`PERSIST_MAX_AGE_MS`) = on ignore et on supprime. `[RN: schema.ts]`
- Hydratation = périmé (`fetchedAt = .distantPast`), donc l'écran se peint depuis le disque puis `ensureFresh` revalide.
- Plafond : 5 propriétaires, éviction du plus ancien.

### 3.4 Contrainte tvOS à vérifier avant D3

tvOS ne garantit pas de stockage persistant : on ne peut compter que sur `Caches` (purgeable par le système quand l'app
n'est pas au premier plan), `UserDefaults` (plafond documenté de 500 Ko) et le Keychain (`ui-plan §13` le dit déjà pour
les téléchargements). Je n'ai pas pu le **vérifier sur appareil dans cette session**. Conséquences retenues :

- Le cache de shelves est jetable par nature : `Caches/` convient et une purge n'est qu'un démarrage à froid.
- **Ce qui ne doit pas être jetable est petit** : la session (Keychain, déjà fait), la file de reports non envoyés (§5.3 :
  quelques entrées après coalescence, dans `UserDefaults`/Keychain, pas dans `Caches`), les réglages locaux
  (`UserDefaults`) et les préférences de pistes par série (§5.4, clés minuscules, `UserDefaults`).
- SwiftData n'est donc pas retenu pour le cache **et** pas pour les réglages (contrairement à `ui-plan §4.1` qui l'évoquait
  pour `AppModel`) : `UserDefaults` suffit pour des réglages de quelques clés. À confirmer par un spike de 30 minutes sur
  simulateur puis Apple TV réelle : écrire dans `Caches/`, `Application Support/`, vérifier la survie au relancement et
  à `simctl` « low storage ».

---

## 4. Connexion, session, 401

Repris de sillon, sans changement de convention.

- `Session` + `SessionStore` (Keychain) : en place. `[sillon: SessionStore.swift ; repo actuel Packages/JellyKit/Sources/LibraryKit/SessionStore.swift]`
- **401 sur requête signée** = jeton révoqué : `JellyfinClient` appelle `onUnauthorized` (closure `@Sendable` passée à
  l'init). À 401 sans jeton (connexion), c'est un mauvais mot de passe, pas une révocation (déjà géré par `authenticate`).
  `AppModel` répond : efface `SessionStore`, jette le `LibraryStore`, retour au choix du profil avec message
  (`ui-plan §10`). Le websocket qui reçoit 401/403 appelle `reportUnauthorized()`. `[sillon: JellyfinClient.swift:53,313]`
- **`ServerReachability`** `@MainActor @Observable`, copié de sillon : `NWPathMonitor` + sonde `/System/Info/Public` (5 s,
  sans auth), trois états `online / offline / serverUnreachable`. Toute erreur réseau d'un client appelle
  `reportFailure`, tout succès `reportSuccess`. Reprend le signal de `monitor.ts` du RN (ping 5 s) avec en plus le
  `NWPathMonitor` « rapide », comme le RN le faisait via `expo-network`. Cadence de sonde : 30 s tant que `serverUnreachable`
  `[RN: monitor.ts REFETCH_INTERVAL_MS]`. `[sillon: Network/ServerReachability.swift]`
- **`AppModel.report(_:otherwise:)`** : erreur réseau = bandeau unique, le reste = alerte de l'écran. `[sillon: AppModel.swift:189 ; ui-plan §4]`

---

## 5. Synchronisation Jellyfin

### 5.1 Reporting de lecture : événements et champs exacts

Jellyfin attend trois appels : `POST /Sessions/Playing` (start), `/Sessions/Playing/Progress`, `/Sessions/Playing/Stopped`.
Côté SDK : `Paths.reportPlaybackStart/Progress(PlaybackStateInfo)` et `reportPlaybackStopped(PlaybackStopInfo)`
`[SDK: Paths/ReportPlayback*API.swift]`.

| Événement | Quand | Champs envoyés `[RN: reporter.ts, use-reporting-session.ts]` | Remarque |
|---|---|---|---|
| Start | au premier `playing` (pas à l'ouverture de l'écran) ; une fois | `ItemId`, `MediaSourceId`, `PlaySessionId`, `PositionTicks` (0 ou point de reprise), `PlayMethod`, `CanSeek: true`, `IsPaused: false`, `AudioStreamIndex?`, `SubtitleStreamIndex?` | Les deux index sont ceux **actuellement joués** (lus depuis mpv), `-1` pour « sous-titres coupés » ; `nil` si inconnus |
| Progress | toutes les **5 s** dans le RN ; **10 s** d'après `lessons-learned.md` (`~10s`) ; en plus immédiat sur pause/reprise, seek, changement de piste | idem + `IsPaused`, `PositionTicks`, `EventName: "timeupdate"` | Voir Q1 sur l'intervalle ; le SDK n'a pas de champ `EventName` dans `PlaybackStateInfo` `[SDK: Entities/PlaybackStateInfo.swift]` : à vérifier qu'il n'est pas requis côté serveur |
| Stopped | fin du fichier, retour de l'écran, fermeture ; une fois | `ItemId`, `MediaSourceId`, `PlaySessionId`, `PositionTicks` | **Sans** index audio/sous-titres : `PlaybackStopInfo` n'a pas ces champs et seul Progress les persiste (`SessionManager.cs:962-1009`, cité par le RN) |

Règles :

1. **`ItemId` et `MediaSourceId` sont deux champs distincts** (défaut du RN, §1). Le résolveur renvoie les deux, le reporter
   les conserve.
2. **Garde de Stop** : pas de `Stopped` tant qu'aucune progression valide n'a été observée ; l'écran de lecteur ouvert puis
   quitté avant la première image ne doit rien écrire. `[RN: use-reporting-session.ts sawProgressRef]`
3. `CanSeek` = `true` (toujours, comme le RN) ; `PlayMethod` = celle du résolveur (§6).
4. Une `PlaySessionId` par lecture, issue de `PlaybackInfo` ; un fichier rejoué après erreur reprend une nouvelle session.
5. **Effets locaux d'un Stop**, appliqués immédiatement au store sans attendre le réseau (règle « répliquer les règles du
   serveur », `[mémoire: optimistic patch + invalidation]`) : voir §5.2 pour la règle de seuil. Puis, **sur succès du
   report seulement**, `markStale([.continueWatching, .nextUp, .seriesNextUp, .adjacentEpisode, .detail, .children,
   .recentlyAdded, .latestMovies, .latestTv, .shelfPage])` (équivalent de `isAffectedQuery` + série/épisode ajoutés,
   §3.1 note 1).

### 5.2 Règle serveur à répliquer localement : seuils de reprise

`UserDataManager.UpdatePlayState` `[serveur: Emby.Server.Implementations/Library/UserDataManager.cs, lu en ligne cette
session, pas reproduit verbatim]` : avec `pctIn = position / runtime`, pour un item de durée connue :

- `pctIn < MinResumePct` : position remise à 0, non vu ;
- `pctIn > MaxResumePct`, ou à moins d'une seconde de la fin : position remise à 0, **vu** ;
- sinon si `runtime < MinResumeDurationSeconds` : position remise à 0, vu ;
- sinon : `PlaybackPositionTicks = position`, non vu.

Les trois seuils sont des champs de la configuration serveur (`ServerConfiguration`), lisibles via la configuration système.
**Je n'ai pas relevé leurs valeurs par défaut dans cette session** ; l'implémentation les lira sur le serveur (ou, à
défaut, les valeurs documentées par le serveur de référence, à vérifier) plutôt que de les coder en dur. Cette fonction ne
touche pas `PlayCount` (confirmé dans le source lu) ; l'incrément de `PlayCount` est fait ailleurs côté serveur, donc le
patch local « vu » garde la règle RN `playCount = max(1, playCount)` en approximation, rectifiée par `UserDataChanged`
(§5.5). **(nouveau : le RN n'appliquait aucun seuil local à l'arrêt, il invalidait seulement.)**

### 5.3 File de reports hors ligne et drain

État RN : `pending-store.ts` (MMKV, clé triée `ts:seq:itemId:kind`, plafond 500, FIFO) + `use-report-drainer.ts`
(drain au passage `non-online → online`). Transposition :

- **`ReportJournal`** (acteur, fichier JSON atomique, propriétaire dans chaque entrée) ; stockage dans `UserDefaults`
  ou un fichier de `Application Support` selon le spike §3.4, **pas** dans `Caches` (§3.4).
- **Coalescence à l'écriture** : par `PlaySessionId`, on garde au plus : le `Start` s'il n'a pas pu partir, **la dernière**
  `Progress`, et le `Stopped`. Une coupure de 2 h ne produit plus 1 440 entrées mais 3. Plafond de sécurité : 50 sessions.
  **(nouveau ; corrige le plafond 500 du RN)**
- **Envoi** : on tente d'abord le réseau, sauf si `ServerReachability` ne vaut pas `online` (court-circuit direct vers la
  file, comme `isKnownOffline` du RN). `[RN: reporter.ts]`
- **Drain** (acteur `PlaybackReporter`, une passe à la fois, `running` flag) : déclenché (a) au passage `online`, (b) au
  lancement de la session, (c) à la fin d'une lecture. Plus ancien d'abord. **Une entrée sort du journal seulement après
  acceptation par le serveur**, ou réponse 404/400 (item disparu : jamais acceptable, on journalise et on abandonne).
  **401** : arrêter, appeler `onUnauthorized`. **Toute autre erreur** : arrêter la passe, conserver le reste, attendre le
  prochain déclencheur. `[sillon: Listens/ListenSync.swift]`
- Un `Stopped` rejoué plus tard met à jour la position serveur ; les `Progress` rejoués pour une session déjà terminée
  sont ignorés si un `Stopped` plus récent existe pour la même `PlaySessionId`.
- Les reports sont conservés après déconnexion de l'utilisateur uniquement si l'utilisateur est le même qu'à la
  reconnexion (propriétaire).
- Le journal est ré-enregistré **avant** toute tentative d'envoi qui peut échouer ; jamais « vider puis rejouer ».

### 5.4 Mémorisation des sélections audio/sous-titres (PR #24, règles exactes)

**Écriture serveur** `[commit 24c601c ; RN: reporter.ts]` : chaque Start et Progress porte `AudioStreamIndex` /
`SubtitleStreamIndex` (courants, lus sur mpv ; `-1` = sous-titres coupés). Le serveur ne les persiste que si l'utilisateur a
`RememberAudioSelections` / `RememberSubtitleSelections` activés ; le client n'a pas à refléter ce réglage côté envoi.

**Lecture serveur** : `MediaSource.DefaultAudioStreamIndex` / `DefaultSubtitleStreamIndex` dans la réponse `PlaybackInfo`.
`-1` conservé tel quel côté sous-titres.

**Mémoire locale** `[RN: services/settings/track-pref.ts]` : clé `(userId, itemKey)` où `itemKey` = `seriesId` pour un
épisode et `itemId` pour un film `[RN: features/player/screens/player-screen.tsx:52]`. Valeur :

```
enum TrackPref {
  case off(ts)                                               // sous-titres seulement
  case lang(language, isExternal, index, ts)                 // l'index n'est qu'un indice de départage
}
```

Écrite quand l'utilisateur choisit une piste dans le sélecteur et que `RememberAudio/SubtitleSelections` est activé et que
la piste a une langue ; `off` écrit à la désactivation des sous-titres. Lue seulement si le réglage serveur est activé
(désactiver le réglage arrête la restauration sans effacer les données). `[RN: use-resolver-settings.ts]` Effacée à la
suppression du profil (`clearTrackPrefsForUser`). Version de schéma dans le préfixe de clé (`v1:`) : changer la forme = clé
illisible plutôt que convertie.

**Chaîne de priorité** `[RN: services/playback/resolver.ts « Priority chain » ; jellyfin-web playbackmanager]` :

Audio :

1. Mémoire locale `lang` → pistes de cette langue (insensible à la casse), en préférant `isDefault`, sinon la première.
   `off` est ignoré (l'audio ne se coupe pas).
2. `DefaultAudioStreamIndex` du serveur **si** l'index existe encore dans `MediaStreams` (fichier retraité = index
   caduc, `MediaSourceManager.cs:403,432`).
3. Préférence de langue (`audioLanguagePreference`) → `isDefault` parmi les correspondances → sinon `isDefault` du
   fichier → sinon la première piste.

Sous-titres :

1. Mémoire locale `off` → pas de sous-titre, la chaîne s'arrête. `lang` → pistes de cette langue ; parmi elles, même
   type (externe/embarqué) que celui mémorisé en priorité, puis `isDefault`, sinon la première. Aucune piste dans cette
   langue sur cet item = on passe à l'étape suivante.
2. Serveur : `DefaultSubtitleStreamIndex == -1` → pas de sous-titre ; index valide → cette piste.
3. Mode `subtitleMode` : `None` = rien ; `OnlyForced` = première piste forcée (préférer `isDefault`), sinon rien ;
   `Smart` = sous-titre seulement si la langue audio choisie diffère de `subtitleLanguagePreference` ; `Default` / `Always`
   (et `Smart` avec audio étranger) = piste dans la langue préférée (préférer `isDefault`), sinon `isDefault` du fichier,
   sinon la première.

Défauts RN à traiter nativement (pas encore résolus dans le RN) `[mémoire: player pending bugs 2026-04-19 ; lessons-learned]` :
**langue de sous-titres préférée non sélectionnée au chargement**, **bouton skip-intro**, **autoplay épisode suivant**.
Le dernier est cadré par la gate RN : zone « crédits » si un segment existe et qu'un épisode suivant est connu ;
sinon fenêtre de fin quand `20 s ≤ restant ≤ 40 s` (≥ 3 000 s de durée), `35 s` (≥ 2 400 s), `30 s` sinon, uniquement
pour les contenus ≥ 600 s ; compte à rebours de 10 s `[RN: features/player/state/end-of-episode-gate.ts]`. L'épisode suivant se
lit via `adjacentEpisode` (`StartItemId` + `Limit 2`). **Le subtitle forcé `sid=no` doit être explicite au chargement**
(le RN avait un bug où mpv ré-activait seul une piste par défaut) `[commit 24c601c, second correctif]`.

**Mapping mpv** : les sous-titres externes sont toujours `sub-add`és, donc `sid` = embarquées d'abord puis externes ;
`computeSubtitleSid` à réimplémenter avec ses tests `[mémoire: mpv subtitle sid mapping ; RN: resolver.ts]`. L'audio est
toujours embarqué : `aid = position + 1`.

**Sortie d'API proposée** (`PlaybackEngine`) :

```
struct TrackSelectionInput { userConfig, rememberedAudio?, rememberedSubtitle? }
struct TrackSelection { audioIndex?, subtitleIndex?, subtitleDelivery? }   // pur, testé
```

### 5.5 Websocket : le RN n'en avait pas

Constat : aucune occurrence de `WebSocket` dans `apps/` ni `packages/` du RN. Tout rafraîchissement était fondé sur
`staleTime`, polling (`refetchInterval`) et invalidation locale. La Phase 3 a décidé de les ajouter `[ui-plan §4.3, §9.1]` ;
le SDK le fournit : `client.socket().connect()` → `Session.events` (`.connecting`, `.connected`, `.disconnected`,
`.message(OutboundWebSocketMessage)`), reconnexion exponentielle, keep-alive 20 s, fin sur 401/403
`[SDK: JellyfinSocket/JellyfinSocket.swift]`. Pattern de consommation éprouvé : `LibraryChangedListener` de sillon.

| Message serveur | Contenu | Action |
|---|---|---|
| `UserDataChanged` | `UserDataChangeInfo.userDataList: [UserItemDataDto]` (`itemID`, `isPlayed`, `playbackPositionTicks`, `playedPercentage`, `isFavorite`, `playCount`, `lastPlayedDate`, `unplayedItemCount`) + `userID` `[SDK: Entities/UserDataChangeInfo.swift, UserItemDataDto.swift]` | Ignorer si `userID` ≠ session. **Appliquer chaque dto à `userData[itemID]`** (zéro refetch d'item). Puis `markStale([.continueWatching, .nextUp, .seriesNextUp])` car l'appartenance et l'ordre de ces listes sont décidés par le serveur. Débouncer 2 s |
| `LibraryChanged` | `LibraryUpdateInfo` : `itemsAdded/Updated/Removed`, `foldersAddedTo/RemovedFrom` | Retirer `itemsRemoved` de `items`, `shelves`, `details` ; `markStale([.recentlyAdded, .latestMovies, .latestTv, .views])` ; débouncer **2 s** (un scan envoie des rafales) `[sillon: LibraryChangedListener debounce]` |
| `.connected` après une coupure | — | Des événements ont pu être manqués : `markStale` de tout + drain de la file de reports (§5.3) `[sillon: LibraryChangedListener.swift « hadConnection »]` |
| `UserUpdated` | utilisateur modifié | `markStale([.config])` (préférences de lecture) |
| `UserDeleted` | utilisateur supprimé | si c'est la session : `reportUnauthorized()` |
| `ServerRestarting`, `ServerShuttingDown` | — | passer `ServerReachability` à `serverUnreachable` sans attendre le prochain ping (`[ui-plan §9.1 « Temps réel »]` liste `ServerRestarting`) |
| `RestartRequired`, `Sessions`, `ActivityLog`, `Play`, `Playstate`, `GeneralCommand`, `SyncPlay*`, plugin, tâches planifiées, minuteries | — | ignorés en v1. Réservés : `Play`/`Playstate`/`GeneralCommand` = télécommande (v1.1), `SyncPlay` (v1.1) `[ui-plan §13]` |

Si le socket est fatal (`unauthorized`), on n'essaie pas de reconnecter ; le reste, le SDK reconnecte seul.
Le websocket ne tourne que pendant que l'application est active ; au retour au premier plan, `.connected` redéclenche la
revalidation.

### 5.6 `UserData` : vu, favori, progression — optimiste avec rollback

Parce que `userData` est normalisé (D2), toutes les mutations suivent le même canevas :

```
func mutateUserData(_ itemIDs, _ transform) async throws:
    1. annuler les tâches inflight des ressources touchées          // RN: cancelQueries
    2. snapshot = itemIDs.map { userData[$0] }                      // une entrée par item, pas 5 familles
    3. userData[$0] = transform(userData[$0])                      // patch local TOUJOURS, hors ligne compris
    4. try await client.<appel serveur>
         succès  → markStale(ensemble de la mutation)               // invalidation SEULEMENT sur succès
         erreur  → userData[$0] = snapshot ; report(error)          // rollback, pas d'invalidation
```

`[RN: use-played-state.ts]` (corrigé : invalidation sur succès seulement), `[mémoire: optimistic patch + invalidation]`.
Une mutation faite hors ligne : le patch local reste et l'appel est ajouté à une file de mutations (même mécanisme que le
journal §5.3, type `markPlayed/markUnplayed/favorite`) **(nouveau ; le RN ne mettait pas ces mutations en file, il
rollbackait)**. Si l'on ne veut pas de file de mutations en v1, hors ligne = rollback + bandeau : voir Q2.

Règles de patch (répliquent le serveur) :

| Mutation | Patch local | Appel SDK | Ensemble invalidé (succès) |
|---|---|---|---|
| Marquer vu (film / épisode) | `played = true`, `playCount = max(1, playCount)`, `lastPlayedDate = now`, **position conservée** `[RN: patchMediaItemPlayed]` | `markPlayedItem` | `continueWatching, nextUp, seriesNextUp, adjacentEpisode, detail, children, recent*, shelfPage` |
| Marquer non vu | `played = false`, `playCount = 0`, `playbackPositionTicks = 0`, `lastPlayedDate = nil`, progression à 0 `[RN]` | `markUnplayedItem` | idem |
| Marquer vu un épisode, effet sur la **série parente** | seul `lastPlayedDate = now` ; `unplayedItemCount` laissé à la revalidation `[RN: patchMediaItemPlayed seriesHit]` | — | la fiche série est marquée périmée |
| Favori / « Ma liste » | `isFavorite` | `markFavoriteItem` / `unmarkFavoriteItem` | `favorites` (liste Ma liste), détail |
| Arrêt de lecture (effet local) | selon les seuils §5.2 | report Stopped | §5.1 règle 5 |
| Mise à jour de `UserConfiguration` | fusion partielle sur la copie locale ; **envoyer la forme complète** (le endpoint remplace l'enregistrement) `[RN: use-user-configuration.ts]` | `updateUserConfiguration` | sur succès : **reposer la copie confirmée par le serveur** (il peut normaliser, `""` → `null`) |

Après un marquage « vu » en cascade (saison/série), c'est le serveur qui cascade ; on patche localement les ids connus et
`markStale` les listes d'enfants.

---

## 6. Resolver et device profile

Module `PlaybackEngine`, sans UIKit, tests purs. `[ui-plan §4.1 ; plan de reboot Phase 2]`

### 6.1 Position

On a mpv : le but est **DirectPlay maximal, zéro transcodage** `[mémoire: reboot Apple TV, lessons-learned « Resolver »]`. Le
profil RN `buildDeviceProfile` sert de base `[RN: packages/api/src/playback.ts:46-176]`. Le profil est **un paramètre**, pas
une constante `[plan de reboot]` ; on garde `maxBitrate` en argument (plafond utilisateur, défaut 120 Mbps).

### 6.2 Profil proposé

Reproduit le profil RN (même table), en notant ce qui change pour tvOS :

- `MaxStreamingBitrate` et `MaxStaticBitrate` = plafond utilisateur ou 120 000 000.
- **DirectPlayProfiles** vidéo : conteneurs `mkv,mp4,m4v,mov,avi,ts,wmv,flv,webm` ; vidéo `h264,hevc,vp9,av1,mpeg4,vc1` ;
  audio `aac,mp3,ac3,eac3,dts,truehd,flac,opus,vorbis,pcm`. Profil audio : `mp3,aac,flac,ogg,opus,wav`.
  tvOS : `ts` reste, `mpeg2video` et `vp8` absents du profil RN ; à ajouter si le catalogue d'Antonin en contient (ffmpeg
  les lit ; aucune raison technique de les exclure) : Q4.
- **CodecProfiles** (obligatoires : §1 règle 14) :
  - `hevc` : `VideoProfile` ∈ `main|main 10`, `VideoRangeType` ∈ `SDR|HDR10|HDR10Plus|HLG|DOVI|DOVIWithHDR10|DOVIWithHDR10Plus|DOVIWithHLG|DOVIWithSDR` ;
  - `h264` : `VideoProfile` ∈ `high|main|baseline|constrained baseline|high 10`, `VideoRangeType = SDR` ;
  - `av1` : mêmes `VideoRangeType` que `hevc` ;
  - `VideoAudio` : `AudioChannels ≤ 8`.
  Toutes les conditions en `IsRequired: false`.
- **TranscodingProfiles** : `ts`, h264, aac, `hls` — dernier recours. `[RN]`
- **SubtitleProfiles** (strings canoniques de `NormalizeSubtitleCodec`) : voir 6.3.
- tvOS spécifique : `deviceName` = « Apple TV », `DeviceProfile.Name` renseigné ; pas de passthrough bitstream (limite
  assumée `[lessons-learned « Audio »]`) donc on laisse `truehd`/`dts` en DirectPlay, mpv décode en PCM multicanal.

### 6.3 Strings de sous-titres canoniques

Correspondent à `MediaStream.Codec` après `NormalizeSubtitleCodec` (`MediaBrowser.MediaEncoding/Probing/ProbeResultNormalizer.cs`),
comparés sans casse `[RN: playback.ts commentaire SubtitleProfiles ; mémoire: Jellyfin subtitle profile canonical ; lessons-learned]` :

`Embed` : `subrip`, `srt`, `ass`, `ssa`, **`pgssub`** (jamais `pgs`), `dvdsub`, `dvbsub`, `dvbtxt`, `mov_text`, `vtt`.
`External` : `srt`, `vtt`, `ass`, `ssa`.

Test unitaire obligatoire : une fixture `MediaSource` avec flux PGS et un `PlaybackInfoResponse` simulé vérifient que la
liste de profils contient `pgssub` et pas `pgs`, car l'erreur « tue le DirectPlay silencieusement ». Le profil est
fabriqué avec les types du SDK (`DeviceProfile`, `SubtitleProfile`, `SubtitleDeliveryMethod.embed/.external`) et un test
compare sa sérialisation au profil RN de référence (fixture).

### 6.4 Arbre de décision

`POST /Items/{id}/PlaybackInfo` (SDK `getPostedPlaybackInfo`), corps `{ DeviceProfile, EnableDirectPlay: true,
EnableDirectStream: true, EnableTranscoding: true, AutoOpenLiveStream: true }` `[RN: fetchPlaybackInfo]`, avec en plus
`mediaSourceID`, `audioStreamIndex`, `subtitleStreamIndex`, `startTimeTicks`, `maxStreamingBitrate` `[ui-plan §9.1]`.
`UserId` en paramètre. Réponse : `MediaSources` (prendre la première, comme le RN, **ou celle demandée si l'utilisateur a
choisi une version**), `PlaySessionId`.

```
src = MediaSources[0]                    // ou la version choisie
si src.SupportsDirectPlay:    PlayMethod = .directPlay
      url = /Videos/{itemId}/stream?Static=true&MediaSourceId=…&api_key=<jeton>
sinon si src.SupportsDirectStream: PlayMethod = .directStream
      url = /Videos/{itemId}/stream.<container>?Static=true&MediaSourceId=…&api_key=…
sinon si src.TranscodingUrl:  PlayMethod = .transcode
      url = <base> + TranscodingUrl
sinon: erreur « aucune source lisible »
```

`[RN: playback.ts parsePlaybackInfo]`. Le repo actuel a déjà `streamURL` (DirectPlay statique) `[repo: LibraryKit/JellyfinClient.swift]`.
`api_key` dans l'URL : requis (mpv ne peut pas poser d'en-têtes) mais **l'URL ne doit jamais être journalisée ni
persistée** **(nouveau)** ; le RN mettait aussi le jeton dans les URL de trickplay.

Autres points :

- **Pas de cache de `PlaybackInfo`** (staleTime 0, §3.1).
- Le plafond de débit utilisateur change → rien à invalider : on n'en garde aucun.
- AV1 4K sur A15 : pas de décodage matériel ; le resolver doit pouvoir basculer en Transcode serveur après mesure
  `[lessons-learned « Resolver » ; plan de reboot, risque AV1]` : le profil est un paramètre, une variante « sans av1 » le
  permet.
- Chapitres : `PlaybackInfo` n'en contient pas ; les lire de `BaseItemDto.chapters` de la fiche (le RN faisait un GET
  parallèle `/Users/{uid}/Items/{id}`) → pas d'appel parallèle dès que la fiche est dans le store.
- Segments (intro/crédits) via `getItemSegments` (Jellyfin ≥ 10.10), en remplacement du plugin `IntroSkipperSegments` du RN ;
  l'absence de segment n'est jamais une erreur.

---

## 7. Images

Décision : **Nuke** (`ImagePipeline` + cache disque 500 Mo, cache mémoire par défaut) `[ui-plan §4.3 ; plan de reboot]`.
Sillon utilise un `ImageCache` maison (`NSCache` + `URLCache` 300 Mo) `[sillon: Images/ImageCache.swift]` ; ici, on suit le
plan de reboot (Nuke), pour le préchargement (`ImagePrefetcher`), la dé-duplication native et la priorité par requête. Ce
n'est pas un cache de données : il reste hors du `LibraryStore`.

- URL construites, pas téléchargées par le client : `getItemImage` (SDK `sdk.url(with:)`) avec `tag` = `ImageTags[type]`
  du DTO. Le `tag` rend l'URL immuable : cache durable, invalidation gratuite quand l'image change.
  `[repo actuel: LibraryKit/JellyfinClient.swift imageURL]`
- Tailles (`ui-plan §9.3`) : affiche `maxWidth 500` (2× 250), paysage 800, backdrop 2560, logo 900, personne 400 ; qualité
  90 (valeur du RN : `quality=90` `[RN: shelves.ts buildPrimaryImageUrl]`).
  Le RN demandait 400 (affiche) / 1280 (backdrop) pour un écran mobile ; pour 1920×1080 on double (décision `ui-plan`).
- Flou : `ImageBlurHashes` du DTO affichés sous 30 ms (`ui-plan §9.3`). Les champs `ImageBlurHashes` doivent être
  demandés.
- Priorités (règle RN : « hero high, shelves below the fold low ») `[CLAUDE.md RN, section Performance]` : billboard et
  carte focalisée `.high`, shelves visibles `.normal`, hors écran `.low`. Préchargement de la ligne suivante pendant le
  défilement. Le `recyclingKey` du RN devient l'identité Nuke par `ItemID+tag`.
- Séries : une carte d'épisode « À suivre » utilise l'image **de la série** pour l'affiche (portrait) `[RN: shelves.ts fetchNextUp, posterUrl: seriesId]`,
  et la miniature de l'épisode (`Primary` ou `Thumb`) pour les cartes paysage.
- Le jeton n'est **pas** dans les URL d'image si le serveur les sert sans authentification (c'est le cas par défaut pour les
  images d'item) ; à vérifier sur un serveur à `RequireAuthentication`.

---

## 8. Ordre de construction et ce que devient la Phase 2

### 8.1 État actuel (commits sur `main`)

Existe : `LibraryKit` avec `JellyfinClient` (`authenticate`, `quickConnect`, `latestMedia`, `resume`, `nextUp`, `imageURL`,
`streamURL`), `Session`, `SessionStore` (Keychain), `MediaItem` (7 champs). Les trois méthodes `latestMedia/resume/nextUp`
renvoient des `MediaItem` complets : c'est une façade de **spike**. Elles sont conservées comme couche HTTP, mais le modèle
`MediaItem` se scinde (D2) en `MediaItem` (métadonnées) + `UserData`, et les méthodes de la façade passent à des
signatures qui renvoient les DTO bruts nécessaires aux mappers (`Presentation/`, `ui-plan §4.1`).

### 8.2 Phase 2 révisée

| Lot | Contenu | Dépend de | Tests (swift-testing) |
|---|---|---|---|
| **2.0** Plomberie | `LibraryAPI` (protocole), `onUnauthorized` dans `JellyfinClient`, `ServerReachability` (copie sillon), `Staleness`, `Stamped`, `UserFacingError` | existant | unitaires purs ; réseau par `URLProtocol` |
| **2.1** Store | `LibraryStore` (items, userData, shelves, inflight, `ensureFresh`, `mutateUserData`, `markStale`), `SnapshotStore`, hydratation périmée | 2.0 | table de fraîcheur ; hydrate-puis-revalide ; rollback ; dédoublonnage ; changement de propriétaire |
| **2.2** Playback engine | `DeviceProfile` tvOS, `PlaybackResolver` (arbre §6.4), `TrackSelection` (§5.4), `computeSubtitleSid`, tests de profil canonique | 2.0 | fixtures `PlaybackInfoResponse` ; priorités audio/sous-titres (reprendre les cas du RN `resolver.test.ts`, `track-pref.test.ts`) |
| **2.3** Reporter | `PlaybackReporter`, `ReportJournal`, drain, coalescence, garde de Stop, effets locaux §5.1-5.2 | 2.1, 2.2 | file hors ligne : coalescence, abandon 404, arrêt sur 401, crash en cours de drain |
| **2.4** Websocket | `ServerEvents` (débounce, rattrapage au `.connected`) | 2.1 | injection manuelle d'événements, sans socket (`init` de test comme sillon) |
| **2.5** Mutations | vu / favori / `UserConfiguration`, optimiste + rollback | 2.1 | rollback sans invalidation ; patch hors ligne |

Position dans le plan UI : 2.0-2.1 avant le lot **3.1** (Auth) car `AppModel` détient le store ; 2.2 avant **3.2** (lecture
directe depuis une carte avec resolver, déjà prévue `[ui-plan §11]`) ; 2.3 avant **3.4a** ; 2.4 et 2.5 avant **3.3**
(« mutations optimistes (vu, ma liste) »). Le lot **3.0** (DesignSystem, galerie sans serveur) ne dépend d'aucun lot de
cette couche et peut avancer en parallèle.

Ordre recommandé des lots : 2.0 → 2.1 → (3.0 en parallèle) → 2.2 → 2.3 → 3.1 → 3.2 → 2.4/2.5 → 3.3 → 3.4.

### 8.3 Ce qu'on ne construit pas

Cache générique, observers, `gcTime`, polling Jellyseerr/Radarr, téléchargements locaux, SwiftData pour le cache,
persistance des fiches détaillées en v1, SyncPlay/télécommande (le socket est branché, les messages ignorés).

---

## 9. Questions ouvertes pour Antonin

| # | Question | Reco |
|---|---|---|
| Q1 | Intervalle des reports Progress : 5 s (RN) ou 10 s (`lessons-learned.md`) ? Le RN a fonctionné à 5 s ; jellyfin-web est la référence de l'écosystème. | 10 s + événements immédiats (pause, seek, changement de piste) ; mesurer l'impact serveur avant de descendre |
| Q2 | Mutations faites hors ligne (vu, favori) : file persistante rejouée au retour, ou rollback + bandeau ? La file coûte un type d'entrée de plus dans le journal et pose la question des conflits (autre client ayant changé entre-temps). | File pour les reports de lecture (obligatoire), **rollback + bandeau pour les mutations manuelles** en v1 ; passer à la file si l'usage la réclame |
| Q3 | Persister les fiches détaillées (le RN le faisait) ou seulement l'accueil ? Persister l'accueil donne le « premier rendu à froid » ; les fiches sont rarement rouvertes hors ligne. | Accueil seul en v1 (`ui-plan §4.3` : l'exception est la Home) ; ajouter si l'usage le demande |
| Q4 | Étendre la liste de codecs DirectPlay (`mpeg2video`, `vp8`, `wmav2`…) ? mpv les lit ; le profil RN ne les listait pas. | Oui pour `mpeg2video` (DVD rips) et `vp8`, après essai sur ton catalogue ; zéro transcodage est l'objectif |
| Q5 | Déconnexion d'un profil : on efface les snapshots et préférences de ce profil ; passer à un autre profil **conserve** son snapshot (reprise rapide). Le RN effaçait tout au changement. OK ? | Oui (multi-profil de premier rang sur Apple TV) |
| Q6 | Stockage tvOS : accepter le spike §3.4 (30 min, simulateur + Apple TV réelle) avant le lot 2.1 ? Il décide du lieu de `ReportJournal` et des préférences de pistes. | Oui, premier acte du lot 2.1 |
| Q7 | Versions multiples d'un même item (plusieurs `MediaSources`) : sélecteur de version dans la fiche v1, ou toujours la première comme le RN ? Le défaut RN `itemId = mediaSourceId` montre que ce cas n'avait pas été exercé. | Première source par défaut ; champ `mediaSourceID` déjà dans le contrat du resolver pour le sélecteur (v1.1) |
| Q8 | `staleTime` hérités du Rust (60 s / 2 min / 5 min / 30 min) : les reprendre tels quels ou les revoir une fois le websocket en place ? Le websocket rend la plupart des TTL de listes inutiles comme source de vérité ; ils deviennent un filet de sécurité. | Reprendre tels quels pour v1 (on dispose d'un historique d'usage, pas de mesure) ; mesurer le trafic réel avant de relâcher |
| Q9 | Valeurs de `MinResumePct`, `MaxResumePct`, `MinResumeDurationSeconds` : lues dynamiquement sur le serveur (recommandé) ou figées ? Je n'ai pas relevé leurs valeurs par défaut. | Lire sur le serveur au démarrage de session (`getConfiguration`), repli documenté si indisponible (non administrateur : à vérifier si l'endpoint est accessible à un simple utilisateur) |
| Q10 | `EventName: "timeupdate"` : le RN l'envoie ; le type `PlaybackStateInfo` du SDK n'a pas ce champ. Garder la conformité au SDK (champ absent) ? | Oui ; vérifier sur un serveur 10.10 et 10.11 que la progression est bien enregistrée (point de contrôle du lot 2.3) |

---

## Annexe A. Points vérifiés / non vérifiés

Vérifié dans cette session :

- Contenu des fichiers RN cités ; présence d'aucun websocket dans `apps/`, `packages/` (grep `WebSocket`).
- Types du SDK : `PlaybackStateInfo`, `PlaybackStopInfo`, `DeviceProfile`, `SubtitleProfile`, `UserItemDataDto`,
  `UserDataChangeInfo`, `LibraryUpdateInfo`, `OutboundWebSocketMessage`, `JellyfinSocket.Session`.
- `UserDataManager.UpdatePlayState` côté serveur (logique de seuils lue en ligne, pas reproduite).

Non vérifié (à faire pendant les lots) :

- Comportement de stockage tvOS sur appareil réel (§3.4).
- Valeurs par défaut de `MinResumePct`, `MaxResumePct`, `MinResumeDurationSeconds`.
- Que `PlaybackStateInfo` sans `EventName` est accepté par 10.10/10.11 (Q10).
- Que les URL d'image soient servies sans authentification sur le serveur cible.
- Le détail de `SessionManager.cs:962-1009` cité par le RN (non relu ici).
- Les temps de mise à jour : tous les `staleTime` sont des valeurs héritées, aucun n'a été mesuré.

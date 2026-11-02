# Décisions produit — 2026-11-02 (validées par Antonin)

Plans ui-plan.md + data-plan.md validés tels quels (« seems good je valide »), recos retenues :
- Identité : wordmark jellyfuse, accent violet #8A6CFF → rose #FF5C8A. Icône app à dessiner.
- Navigation : TabView natif tvOS (Accueil, Films, Séries, Recherche, Réglages).
- Ma liste = favoris Jellyfin. PIN de profil local gardé en v1. tvOS 17 minimum.
- Langues v1 : fr + en. Bibliothèques mixtes/perso : masquées en v1.
- Data : progress 10 s + événements immédiats ; mutations offline = rollback + bandeau ;
  persistance disque Accueil seul ; snapshots par profil ; staleness hérités du RN puis mesurés ;
  DirectPlay étendu (mpeg2video, vp8) ; seuils de reprise lus du serveur.

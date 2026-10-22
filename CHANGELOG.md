# Nouveautés de Clémentine

## 1.0.17 — 22 octobre 2026

- Finovox reste activé sur les installations existantes ; le défaut désactivé concerne uniquement les nouvelles installations. Le choix effectué ensuite dans Réglages est conservé.
- Print : bouton de fermeture pour annuler le dialogue macOS, sans bouton vert d’agrandissement.
- 62 contrôles de disponibilité, de migration des préférences et de préparation d’impression réussis sans fenêtre de test ni impression envoyée.

## 1.0.16 — 22 octobre 2026

- Sources, documentation, installateurs et mises à jour réunis dans le dépôt public Josephggx/clementine.
- Migration du flux de mise à jour vers ce dépôt ; une release de transition conserve la compatibilité avec les installations existantes.


## 1.0.15 — 22 octobre 2026

- Print dans Actions pour PDF, documents, tableurs, images et présentations. Ouvre le dialogue d’impression macOS ; les sélections multiples préparent un seul travail sans modifier les originaux.
- Préférence « Ouvrir dans Finovox » en dernier dans Préférences, désactivée par défaut. Masque l’action dans la roue, l’Atelier et les démonstrations tant qu’elle n’est pas activée.
- 53 contrôles de disponibilité et de préparation d’impression réussis sans fenêtre de test ni impression envoyée.
- Installateur complet et correctifs directs depuis les versions 1.0.1 à 1.0.14.

## 1.0.14 — 22 octobre 2026

- Float : surface native d’interaction indépendante du rendu glass ; le fond capture les clics et le déplacement, les fichiers reçoivent leurs événements directement.
- Croix native et dépôts de fichiers gérés par la même surface ; comportement de fenêtre persistante distinct de la roue.
- Huit contrôles natifs de routage passent sans fenêtre ni activation d’application. Le comportement au-dessus des autres apps reste à vérifier graphiquement.
- Installateur complet et correctifs directs depuis les versions 1.0.1 à 1.0.13.

## 1.0.13 — 22 octobre 2026

- Float : le fond, les fichiers et la croix acceptent le premier clic quand une autre app est active, sans activer l’Atelier.
- Float utilisable pendant les dialogues de Clémentine.
- Compilation et signature vérifiées ; aucun test graphique exécuté pour cette version.
- Installateur complet et correctifs différentiels directs depuis les versions 1.0.1 à 1.0.12.

## 1.0.12 — 22 octobre 2026

- Corrige le crash à la fermeture de l’aperçu Atelier : Quick Look assure une seule fermeture, y compris avec la croix, Échap ou un clic extérieur.
- Les notifications tardives d’un ancien aperçu ne ferment plus le suivant.
- Installateur complet et correctifs différentiels directs depuis les versions 1.0.1 à 1.0.11.

## 1.0.11 — 21 octobre 2026

- Mises à jour directes vers la dernière version, sans installation des versions intermédiaires.
- Catalogue GitHub actualisé à chaque vérification ; les anciens réglages de flux ne peuvent plus conserver une destination dépassée.
- Dix correctifs différentiels directs, depuis les versions 1.0.1 à 1.0.10 vers 1.0.11. Le téléchargement complet reste disponible pour les autres installations et en secours.
- Validation réelle : app de test 1.0.0 mise à jour directement vers 1.0.9 sans correctif compatible, avec remplacement et relance sur la dernière version. Chaque correctif publié est appliqué à sa base puis comparé à la nouvelle app signée.


## 1.0.10 — 21 octobre 2026

- Raccourcis : Maj pour Conversion, Option pour Outils, Commande pour Actions ; migration unique des réglages existants et onboarding actualisé.
- Float : fond glass aussi en mode compact, animation d’ouverture/repli, clic sur le fond pour ouvrir ou replier, glissement pour déplacer ; fichiers sélectionnables séparément.
- Aperçu Atelier : grande fenêtre déplaçable et redimensionnable, défilement et vrai plein écran via le bouton vert.
- Actions Duplicate et Atelier pour tous les fichiers et sélections ; Atelier est masqué dans l’Atelier.
- Toast « Copié ! » près du pointeur pour Copy et Copy Path.
- Dézip dans l’Atelier : ZIP, TAR, GZIP, y compris le GZIP d’un fichier unique. Les fichiers extraits sur disque remplacent l’archive épinglée.
- Survols ZIP Conversion/Outils indépendants ; poubelle à gauche dans les menus de pages Organize/Split.
- Langue de l’onboarding en bas à gauche du bloc de titre.

Installateur complet signé et correctifs différentiels vérifiés depuis les versions 1.0.7, 1.0.8 et 1.0.9.

## 1.0.9 — 21 octobre 2026

- Atelier : le tooltip Finder affiche uniquement le dossier contenant le fichier.
- Renommage : largeur minimale de 100 points, sans placeholder ; libellé accessible conservé.

Installateur signé et correctifs différentiels vérifiés depuis les versions 1.0.6, 1.0.7 et 1.0.8. Les six fichiers de la release sont publiés et leurs empreintes vérifiées.

## 1.0.8 — 21 octobre 2026

Installateur complet et mises à jour différentielles signés, disponibles depuis les versions 1.0.5, 1.0.6 et 1.0.7.

- Interface disponible en français et en anglais, avec choix de langue dans Réglages et en bas à droite de l’onboarding. Le français reste la langue par défaut.
- Onboarding : roue des outils animée sans interaction ; demandes d’autorisation fiabilisées, apps Apple absentes ignorées et boutons débloqués après refus ou expiration.
- PDF : « Merge PDF » devient « Merge ». Split propose un dropdown PDF/JPEG/PNG ; pour PDF, choix « 1 par 1 » ou regroupement personnalisé des pages par glisser-déposer.
- Archives : action Dézip. Le bouton Dézip d’un ZIP épinglé le remplace dans l’Atelier par ses fichiers et dossiers après extraction réussie, en conservant le ZIP original sur le disque.
- Atelier : boutons Renommer et Supprimer sur les éléments épinglés ; confirmation avant déplacement dans la Corbeille. Retirer continue de désépingler uniquement.
- Réglages : le bouton de vérification devient « Rechercher une mise à jour ».

- Split : libellés PDF/Image, insertion de PDF avant/entre/après les groupes, rotation/duplication/suppression de pages et retrait du groupe vidé. Split est proposé uniquement pour les PDF de plusieurs pages.
- Atelier : renommage dans la ligne du document ; suivi des renommages et de la Corbeille, suppression des doublons par identité du fichier et fermeture des outils quand tous leurs fichiers ont disparu. Les autres fichiers restent sélectionnés, y compris après une modification pendant le chargement.
- Atelier : Dézip épingle les fichiers réellement extraits sur disque, icône alignée sur la roue, ordre des commandes ajusté et affichage « 0 ko ». Confirmation native de suppression conservée avec texte raccourci.
- Onboarding : langue sans icône ni libellé à droite de Retour ; changement d’outil toutes les 1,8 seconde.

- Organize et Split personnalisé partagent désormais les mêmes miniatures, menu « … » en capsule glass, icônes et animations, avec un fond discret en fondu au survol de chaque commande. Les commandes de page restent liées à leur identifiant pendant le réordonnancement.

- Roue : fenêtres flottantes indépendantes de l’Atelier, réouvertures bloquées pendant le glissement et après sa fermeture ; une fenêtre Atelier déjà visible n’est plus remise au premier plan par une réouverture implicite. Tests de fenêtres et de glissement ajoutés.

- Atelier : Dézip utilise la même teinte que les autres commandes. Extraction des noms accentués corrigée même sans locale UTF-8 ; les chemins sortants et les liens restent refusés. Renommage au double-clic, champ ajusté au titre avec soulignement discret, extension séparée, commandes Valider/Annuler avec survol et annulation au clic extérieur ; les informations et autres commandes sont masquées pendant l’édition.

- Cohérence fichiers : batterie étendue aux ZIP/dézip répétés, archives multiples, collisions de noms internes, renommages/déplacements externes, liens physiques, copies, Corbeille réelle et vidage pendant extraction. Correction des collisions de noms dans un ZIP et préservation des noms Mac contenant une barre oblique inverse à l’extraction ZIP native. Renommage : refus des noms commençant par un point, en plus des noms invalides ; accents, emoji et symboles autorisés conservés.

## 1.0.7 — 20 octobre 2026

- Atelier : l’aperçu des dossiers utilise une icône de dossier.
- Fonctionnalités : nouvelle catégorie « Dossier » après ZIP, sans sélecteur de format, avec ZIP et les actions adaptées.
- Les dossiers ne proposent ni conversion de document ni Métadonnées, y compris lorsqu’un nom de dossier se termine par une extension de fichier.

Correctifs différentiels disponibles depuis les versions 1.0.4, 1.0.5 et 1.0.6.

## 1.0.6 — 20 octobre 2026

- Métadonnées n’est plus proposé pour les dossiers, dans la roue et l’Atelier. ZIP reste disponible.
- Les dossiers affichent « Dossier » dans la liste et l’aperçu de l’Atelier, au lieu de « Autre ».

Correctifs différentiels disponibles depuis les versions 1.0.3, 1.0.4 et 1.0.5.

## 1.0.5 — 20 octobre 2026

- Corrige la régression d’affichage : les éléments du glisser-déposer restent au-dessus de la roue.
- Recherche automatiquement les mises à jour au lancement, puis toutes les heures en arrière-plan. L’installation reste à votre initiative.

Correctifs différentiels disponibles depuis les versions 1.0.2, 1.0.3 et 1.0.4.

## 1.0.4 — 20 octobre 2026

- Finovox : sélection de l’onglet et du sélecteur Chrome fiabilisée. Le chargement se ferme après remise des fichiers au SaaS, qui gère les doublons et l’analyse.
- Glissements multiples : la roue reste au-dessus de la pile de fichiers du Finder.
- Retour haptique : suppression des impulsions répétées lors du survol avec plusieurs fichiers.
- ZIP : les lots peuvent inclure des archives, tout en masquant l’action ZIP pour une archive seule.
- Onboarding : les animations de découverte ne réagissent plus au passage de la souris.

Correctifs différentiels disponibles depuis les versions 1.0.1, 1.0.2 et 1.0.3. L’installateur complet reste disponible en secours et pour une première installation.

## 1.0.3 — 20 octobre 2026

Disponible depuis **Réglages → Chercher une mise à jour** dans Clémentine, ou via l’installateur pour une première installation.

- Mises à jour différentielles : téléchargement des fichiers modifiés lorsque le correctif est disponible, avec installateur complet en secours.
- Installation : récupération de la relance si l’ancienne instance reste ouverte et vérification de la version réellement démarrée.
- Installateur : fenêtre dédiée au glisser-déposer vers Applications ; l’ouverture depuis le disque d’installation rejoint la copie installée.
- Outils : les petites fenêtres se déplacent depuis leur en-tête, sans déplacer les illustrations de la page Fonctionnalités.
- Atelier : liste de documents limitée à la hauteur de l’aperçu, bouton Vider aligné à droite, suppression du chemin et de son bouton de copie.
- Atelier : infobulles au-dessus des boutons Preview, Finder (chemin complet), Ouvrir et Retirer.
- Métadonnées : disponible uniquement avec un seul fichier sélectionné.
- Terminal : ouverture de chaque dossier distinct de la sélection, sans doublons et avec prise en charge des espaces, accents et caractères spéciaux.

Correctif depuis la 1.0.2 : environ 311 Ko. Correctif depuis la 1.0.1 : environ 341 Ko. Si le correctif ne peut pas être appliqué, le téléchargement complet est utilisé.

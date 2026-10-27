# Clémentine

Application macOS de conversion et de traitement de fichiers. Apple Silicon, macOS 14 minimum.

L’application installée est **`/Applications/Clémentine.app`**. Le dépôt contient uniquement les sources, les ressources nécessaires, les tests et la documentation.

## Version 1.0.19

Version 1.0.19 du 27 octobre 2026 : réunit Crop et Annotate dans Edit, avec recadrage réversible, annotations et sauvegarde combinée, y compris par image dans une sélection multiple. Le dépôt public unique est `Josephggx/clementine`.

## Construire et mettre à jour

Lancer `./build.sh`. La compilation produit `.build/Clémentine.app` et ne remplace pas l’application installée. Les mises à jour sont publiées sur GitHub ; Joseph les installe depuis l’app pour vérifier les changements.

Pour compiler ailleurs : `CLEMENTINE_APP_PATH="/chemin/Clémentine.app" ./build.sh`. Le moteur bureautique est repris de l’app installée s’il est disponible ; sinon `prepare-runtime.sh` le télécharge depuis The Document Foundation.

## Installateurs

Après avoir construit et vérifié `.build/Clémentine.app`, lancer `zsh package-release.sh` pour créer l’installateur standard, ou `zsh package-beta.sh` pour la bêta indépendante. Les fichiers DMG sont placés dans le dossier parent. Ces scripts ne remplacent pas l’app installée.

Le DMG standard conserve exactement le bundle signé du build, sans réécrire son Info.plist ni y ajouter de ressources. Le script compare son contenu extrait au build et, si elle existe, à l’archive ZIP de la même version. Les deux canaux doivent rester identiques pour les correctifs différentiels. Une version ou une identité différente impose de reconstruire avant de préparer le DMG.

Les paquets actuels utilisent une signature locale, sans certificat Developer ID ni notarisation Apple : ils peuvent nécessiter une autorisation manuelle lors de la première ouverture sur un autre Mac.

## Mises à jour

Sparkle 2.10.0 est téléchargé depuis sa publication officielle par `Scripts/prepare-sparkle.sh`, avec vérification SHA-256. Le framework est intégré dans `Contents/Frameworks` ; ses exécutables conservent leur signature officielle.

Le dépôt public unique `Josephggx/clementine` contient les sources, la documentation et toutes les releases. `Josephggx/clementine-releases` est conservé en archive de compatibilité : sa dernière release fournit le flux de transition, sans nouveau développement.

Après compilation et `zsh package-release.sh`, lancer :

```sh
python3 Scripts/prepare-update.py ../Clementine-VERSION-arm64.dmg --notes "Nouveautés de cette version."
```

Remplacer le nom du DMG par celui de la version publiée. Créer une release publique `vVERSION` et joindre le DMG, son fichier `.sha256` et `appcast.xml`. Publier la release seulement après l’envoi des trois fichiers. L’URL stable du flux pointe vers l’asset `appcast.xml` de la dernière release ; chaque téléchargement du flux utilise l’URL immuable du DMG correspondant.

À chaque itération demandée, incrémenter la version et le numéro de build, vérifier le changement, synchroniser les sources et publier la nouvelle release. Ne jamais remplacer les fichiers d’une release déjà publiée : les signatures, URL et versions doivent rester cohérentes. Ne pas remplacer directement `/Applications/Clémentine.app`, sauf demande explicite ; Joseph déclenche la mise à jour pour contrôler le résultat.

L’installateur DMG présente deux vraies icônes Finder sur un fond Retina généré par `Scripts/generate-installer-background.swift`. `Scripts/dmg-settings.py` fixe leurs positions et l’apparence de la fenêtre sans modifier les préférences du Finder. Les outils de packaging restent dans `.build/packaging-python` ; ils ne sont pas intégrés à l’app.

Les commits passent par le connecteur GitHub sur le compte personnel Josephggx. Les releases et leurs fichiers sont publiés depuis Chrome, profil Perso, avec l’exception de publication autorisée par Joseph ; ne pas utiliser le profil Finovox. Ne jamais remplacer l’app installée sans demande explicite.

`Scripts/prepare-update.py` génère désormais le flux signé et les correctifs différentiels depuis toutes les archives locales plus anciennes disponibles. Les archives déjà diffusées sont immuables et conservées pour servir de bases. Il est possible de limiter explicitement les bases avec `--previous-archive`. Chaque correctif est appliqué sur une copie de la base ; signature, contenu, liens symboliques et permissions du résultat doivent correspondre à la nouvelle version avant publication. Le rapport `.build/release-assets.json` liste tous les fichiers à joindre à la même release : archive complète (DMG ou ZIP), correctifs `.delta` et flux signé. Toujours joindre également le SHA-256 de l’archive. Un DMG peut être ajouté ensuite à une release distribuée via ZIP, après vérification que les deux contiennent exactement le même bundle signé ; le flux et les correctifs déjà publiés restent alors inchangés. Si une base est absente ou qu’un correctif ne s’applique pas, Sparkle utilise automatiquement l’archive complète signée. Ne pas publier uniquement le flux sans ses correctifs.

Le moteur bureautique est normalisé une fois par `Scripts/normalize-runtime-signatures.py` : seuls quatre anciens fichiers vides sont retirés, puis la signature de son bundle est refaite. Ceci supprime des signatures détachées en attributs étendus, incompatibles avec une reconstruction différentielle. Les exécutables et bibliothèques du moteur restent identiques.

Après le choix « Installer et relancer », un second appel de terminaison normale effectué par l’app prend le relais si la première demande macOS n’aboutit pas. L’app ne force jamais la fermeture et attend la fin des conversions, y compris dans les modules. Un reçu local de version n’est confirmé qu’après le démarrage effectif sur le build attendu. Si les fichiers sur disque ont déjà été mis à jour mais qu’un ancien processus est resté ouvert, le CTA propose une relance au lieu d’un nouveau téléchargement.

Un lancement depuis le DMG ou une copie transloquée ouvre la copie de `/Applications/Clémentine.app` avant de démarrer les roues, l’onboarding ou les demandes d’autorisation. En l’absence de copie installée, le bouton « Installer et ouvrir » effectue une première copie complète dans Applications. Ce chemin ne remplace jamais une app existante ; les mises à jour restent gérées par Sparkle ou par le glisser-déposer du Finder. Une copie Finder ne peut pas lancer automatiquement l’app : le double-clic suivant ouvre toujours la copie installée.

Le DMG et le flux sont signés en Ed25519. La clé privée est dans le Trousseau macOS sous le compte `io.joseph.clementine.desktop` ; elle n’est ni dans le projet, ni dans les dépôts GitHub. Conserver une sauvegarde sécurisée du Trousseau : perdre cette clé empêcherait de signer les prochaines mises à jour reconnues par les installations existantes.

Les vérifications automatiques restent silencieuses. Le bouton « Mettre à jour » apparaît dans la sidebar lorsqu’une version est disponible ; le clic ouvre l’interface d’installation Sparkle. Aucune installation automatique n’est activée. Une conversion en cours retarde le redémarrage. La version installée figure au bas des Réglages.

## Icône

`Scripts/generate-icon.sh` régénère l’icône macOS multi-résolution depuis `Scripts/generate-icon.swift`. Le PNG intermédiaire reste temporaire et n’est pas inclus dans l’application.

## Tests et documentation

Les scripts `Tests/check-*.sh` exécutent les tests ; les scripts `Tests/build-*.sh` construisent les applications de vérification. Tous les résultats et caches sont recréés dans `.build/`, ignoré par le dépôt.
Pour vérifier les conversions bureautiques et le rendu PDF dans le contexte macOS réel, construire `Tests/check-documents.sh --build-gui`, puis ouvrir l’application de vérification produite dans `.build/`.

Les suites `SelfTests.swift` et `ConversionParityTests.swift` ne font plus partie du binaire normal. Pour les intégrer à une compilation de diagnostic, définir `CLEMENTINE_INTERNAL_TESTS=1` lors de `./build.sh`.

`Docs/Utilisation.txt` décrit les raccourcis et l’action Finovox. `Docs/Validation.json` et les rapports associés conservent les résultats et limites des vérifications, notamment les écarts de parité avec Tangerine. `THIRDPARTY.txt` documente les composants et leurs licences.

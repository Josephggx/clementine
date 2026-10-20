# Clémentine

Application macOS de conversion et de traitement de fichiers. Apple Silicon, macOS 14 minimum.

L’application installée est **`/Applications/Clémentine.app`**. Le dépôt contient uniquement les sources, les ressources nécessaires, les tests et la documentation.

## Construire et mettre à jour

Quitter Clémentine, puis lancer `./build.sh`. La compilation met à jour directement `/Applications/Clémentine.app`, avec le même identifiant. Il faut disposer du droit d’écriture dans Applications. Les préférences sont conservées.

Pour compiler ailleurs : `CLEMENTINE_APP_PATH="/chemin/Clémentine.app" ./build.sh`. Le moteur bureautique est repris de l’app installée s’il est disponible ; sinon `prepare-runtime.sh` le télécharge depuis The Document Foundation.

## Installateurs

Après avoir construit et vérifié `.build/Clémentine.app`, lancer `zsh package-release.sh` pour créer l’installateur standard, ou `zsh package-beta.sh` pour la bêta indépendante. Les fichiers DMG sont placés dans le dossier parent. Ces scripts ne remplacent pas l’app installée.

Les paquets actuels utilisent une signature locale, sans certificat Developer ID ni notarisation Apple : ils peuvent nécessiter une autorisation manuelle lors de la première ouverture sur un autre Mac.

## Mises à jour

Sparkle 2.10.0 est téléchargé depuis sa publication officielle par `Scripts/prepare-sparkle.sh`, avec vérification SHA-256. Le framework est intégré dans `Contents/Frameworks` ; ses exécutables conservent leur signature officielle.

Le dépôt public `Josephggx/clementine-releases` reçoit uniquement les installateurs, empreintes et le flux `appcast.xml`. Le code est conservé dans le dépôt privé `Josephggx/clementine`.

Après compilation et `zsh package-release.sh`, lancer :

```sh
python3 Scripts/prepare-update.py ../Clementine-1.0.1-arm64.dmg --notes "Nouveautés de cette version."
```

Remplacer le nom du DMG par celui de la version publiée. Créer une release publique `vVERSION` et joindre le DMG, son fichier `.sha256` et `appcast.xml`. Publier la release seulement après l’envoi des trois fichiers. L’URL stable du flux pointe vers l’asset `appcast.xml` de la dernière release ; chaque téléchargement du flux utilise l’URL immuable du DMG correspondant.

Le DMG et le flux sont signés en Ed25519. La clé privée est dans le Trousseau macOS sous le compte `io.joseph.clementine.desktop` ; elle n’est ni dans le projet, ni dans les dépôts GitHub. Conserver une sauvegarde sécurisée du Trousseau : perdre cette clé empêcherait de signer les prochaines mises à jour reconnues par les installations existantes.

Les vérifications automatiques restent silencieuses. Le bouton « Mettre à jour » apparaît dans la sidebar lorsqu’une version est disponible ; le clic ouvre l’interface d’installation Sparkle. Aucune installation automatique n’est activée. Une conversion en cours retarde le redémarrage. La version installée figure au bas des Réglages.

## Icône

`Scripts/generate-icon.sh` régénère l’icône macOS multi-résolution depuis `Scripts/generate-icon.swift`. Le PNG intermédiaire reste temporaire et n’est pas inclus dans l’application.

## Tests et documentation

Les scripts `Tests/check-*.sh` exécutent les tests ; les scripts `Tests/build-*.sh` construisent les applications de vérification. Tous les résultats et caches sont recréés dans `.build/`, ignoré par le dépôt.
Pour vérifier les conversions bureautiques et le rendu PDF dans le contexte macOS réel, construire `Tests/check-documents.sh --build-gui`, puis ouvrir l’application de vérification produite dans `.build/`.

Les suites `SelfTests.swift` et `ConversionParityTests.swift` ne font plus partie du binaire normal. Pour les intégrer à une compilation de diagnostic, définir `CLEMENTINE_INTERNAL_TESTS=1` lors de `./build.sh`.

`Docs/Utilisation.txt` décrit les raccourcis et l’action Finovox. `Docs/Validation.json` et les rapports associés conservent les résultats et limites des vérifications, notamment les écarts de parité avec Tangerine. `THIRDPARTY.txt` documente les composants et leurs licences.

# Clémentine

Convertissez et modifiez vos fichiers directement sur votre Mac.

Ce dépôt réunit le code source, les installateurs et les mises à jour de Clémentine.

[![Télécharger Clémentine pour Mac](https://img.shields.io/badge/T%C3%A9l%C3%A9charger_Cl%C3%A9mentine-pour_Mac-f56d30?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Josephggx/clementine/releases/download/v1.0.18/Clementine-1.0.18-arm64.dmg)

**[⬇ Télécharger l’installateur — version 1.0.18](https://github.com/Josephggx/clementine/releases/download/v1.0.18/Clementine-1.0.18-arm64.dmg)**

Mac Apple Silicon (M1 ou ultérieur) · macOS 14 ou ultérieur.

## Installation

1. Téléchargez le fichier **`.dmg`** avec le bouton ci-dessus.
2. Ouvrez-le, puis glissez **Clémentine** dans **Applications**.
3. Lancez Clémentine et suivez le guide de démarrage.

L’app est signée localement, sans notarisation Apple. macOS peut demander une autorisation manuelle lors de la première ouverture dans **Réglages Système → Confidentialité et sécurité**.

<img src="https://github.com/user-attachments/assets/7473d17a-a8e1-463e-80b5-29dcf0c48892" alt="Autoriser Clémentine dans les réglages Confidentialité et sécurité de macOS : Ouvrir quand même" width="700">

## Mises à jour

Clémentine recherche les nouvelles versions au lancement, puis toutes les heures en arrière-plan. Elles sont proposées via le bouton **Mettre à jour**. Vous pouvez aussi vérifier depuis les **Réglages**, à côté du numéro de version.

Une seule mise à jour vous fait passer directement à la dernière version, même si vous avez plusieurs versions de retard. Un correctif différentiel plus léger est proposé lorsqu’il est disponible pour votre version. L’installateur complet reste nécessaire pour une première installation et sert de secours si le correctif ne peut pas être appliqué.

[Consulter les nouveautés](CHANGELOG.md)

## Raccourcis

Glissez un fichier, puis appuyez sur la touche choisie :

- **Maj** : Conversion
- **Option** : Outils
- **Commande** : Actions

[Toutes les versions et nouveautés](https://github.com/Josephggx/clementine/releases)

Les fichiers `.sha256` servent uniquement à vérifier l’intégrité des installateurs. Le fichier `appcast.xml` est utilisé par le système de mise à jour : vous n’avez pas à les télécharger pour installer l’app.

## Construire l’app

Consultez le [guide de développement](Docs/DEVELOPMENT.md) pour compiler, tester et préparer une version. Les dépendances et leurs licences sont détaillées dans [THIRDPARTY.txt](THIRDPARTY.txt).

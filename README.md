<p align="center">
  <img src="pianissimo/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Pianissimo">
</p>

# Pianissimo

Application macOS pour isoler le piano dans un morceau, le transcrire en MIDI et le rejouer — **100 % en local**, sans envoi de données.

## Télécharger

**[⬇ Pianissimo pour macOS](https://github.com/leoacqueberge/pianissimo/releases/latest/download/pianissimo.zip)** (~500 Mo)

Dézippe, glisse l’app dans Applications, puis ouvre-la (clic droit → Ouvrir la première fois si macOS bloque).

## Fonctionnalités

- **Pipeline complet** — séparation des pistes (Demucs) puis transcription piano → MIDI
- **Transcription seule** — à partir d’un fichier audio piano
- **Lecteur MIDI** — lecture avec soundfont piano intégré

Les fichiers produits sont enregistrés dans `~/Music/Pianissimo/`.

## Compiler depuis les sources

```bash
git clone https://github.com/leoacqueberge/pianissimo.git
open pianissimo.xcodeproj
```

Le moteur Python embarqué (`engine/runtime/` et `engine/models/`, ~1 Go) n’est pas versionné. Pour builder avec l’IA, copie le dossier `engine/` depuis `Pianissimo.app/Contents/Resources/` (après avoir installé l’app) vers la racine du projet.

## Licence

Voir le dépôt pour les détails de licence.

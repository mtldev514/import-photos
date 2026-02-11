# import-photos

Script Bash pour importer des photos RAW de maniere selective depuis une carte SD (ou un dossier source), en se basant sur les metadonnees XMP (etoiles, label couleur).

Le script est pense pour un workflow de tri photo avec FastRawViewer, Photo Mechanic ou tout outil qui ecrit des sidecars `.xmp`.

## Ce que fait l'outil

`import-photos` automatise un flux d'import robuste:

1. Lit les fichiers RAW dans un dossier source (recursif ou non).
2. Lit en une passe les sidecars XMP via `exiftool`.
3. Filtre les RAW selon:
   - note minimum (`Rating`)
   - label couleur (`Label`)
   - ou sans filtre (`--no-filter`).
4. Copie les fichiers matches vers un dossier destination.
5. Peut copier aussi les JPG associes (`--with-jpg`).
6. Gere les doublons (demander / forcer / ignorer).
7. Peut verifier l'integrite apres copie (hash source vs destination).
8. Peut memoriser l'historique des imports pour eviter de re-importer les memes fichiers.

## Cas d'usage typique

- Tri initial dans FastRawViewer.
- Attribuer des etoiles/labels.
- Lancer `import-photos` pour ne copier que les fichiers retenus.
- Reprendre le post-traitement depuis un dossier propre de selection.

## Prerequis

- macOS ou Linux (script Bash, compatible macOS Bash 3.2)
- `exiftool` (obligatoire)

Installation `exiftool` sur macOS:

```bash
brew install exiftool
```

## Structure du repo

- `copie_raf_verts.sh` : script principal.
- `import-photos.conf` : exemple de configuration.

## Installation

Depuis le dossier du projet:

```bash
cd /Users/alexcat/Scripts/import-photos
chmod +x copie_raf_verts.sh
```

Optionnel: commande globale `import-photos`:

```bash
ln -sf /Users/alexcat/Scripts/import-photos/copie_raf_verts.sh /usr/local/bin/import-photos
```

## Configuration

Le script lit automatiquement:

```bash
~/.import-photos.conf
```

Creer ce fichier a partir du template fourni:

```bash
cp /Users/alexcat/Scripts/import-photos/import-photos.conf ~/.import-photos.conf
```

Variables importantes:

- `SOURCE_PATH` : dossier source (ex: `/Volumes/FujiFilm/DCIM`)
- `DEST_PATH` : dossier destination
- `RAW_EXTENSIONS` : ex: `RAF` ou `RAF,DNG`
- `MIN_STARS` : note mini (0 desactive)
- `LABEL` : label couleur (ex: `Green`)
- `COPY_JPG` : copier aussi les JPG associes
- `ORGANIZE_BY_DATE` : creer un sous-dossier par date d'import
- `VERIFY_COPY` : verifier hash apres copie
- `TRACK_HISTORY` : eviter les re-imports
- `RECURSIVE` : chercher dans les sous-dossiers

## Utilisation rapide

### 1) Dry-run (recommande)

```bash
./copie_raf_verts.sh --dry-run --stars 3
```

### 2) Import reel (selection 3 etoiles et +)

```bash
./copie_raf_verts.sh --stars 3
```

### 3) Import par label

```bash
./copie_raf_verts.sh --label Green
```

### 4) Import combine (etoiles + label)

```bash
./copie_raf_verts.sh --stars 1 --label Green
```

### 5) Import multi-RAW + JPG

```bash
./copie_raf_verts.sh --ext RAF,DNG --with-jpg
```

### 6) Import sans filtre XMP

```bash
./copie_raf_verts.sh --no-filter
```

## Options principales

- `-s, --stars N` : note minimale (1-5)
- `-l, --label COULEUR` : label XMP (`Red`, `Yellow`, `Green`, `Blue`, `Purple`)
- `--no-filter` : desactive les filtres XMP
- `-d, --dest PATH` : destination
- `--by-date` : destination par date (`YYYY-MM-DD`)
- `-e, --ext LISTE` : extensions RAW (`RAF,DNG,...`)
- `--with-jpg` : inclure JPG associes
- `-y, --doublons` : copier doublons automatiquement
- `-n, --no-doublons` : ignorer doublons automatiquement
- `--no-verify` : desactiver verification integrite
- `--no-history` : ne pas tracer historique
- `--no-recursive` : non recursif
- `--dry-run` : simulation sans copie
- `-h, --help` : aide complete

## Logique de doublons et d'historique

### Historique (`TRACK_HISTORY=true`)

Le script enregistre une cle fichier dans:

```text
<DEST_PATH>/.import_history
```

Cela evite de re-copier un meme original deja importe.

### Doublons en destination

Si un nom cible existe deja:

- mode `ask` (defaut): demande utilisateur
- mode `yes`: suffixe auto `_1`, `_2`, ...
- mode `no`: ignore les doublons

## Verification d'integrite

Si `VERIFY_COPY=true`, le script compare hash source/destination apres copie.

- Si mismatch: le fichier destination est supprime.
- Le compteur d'erreurs d'integrite est incremente en resume final.

## Sortie et resume

Le script affiche:

- nb de fichiers copies
- nb de JPG copies (si actif)
- nb de fichiers ignores (filtres)
- nb de deja importes (historique)
- nb de doublons detectes
- nb d'erreurs d'integrite

## Bonnes pratiques

1. Toujours lancer d'abord en `--dry-run`.
2. Garder `VERIFY_COPY=true` sur cartes SD/lecteurs sensibles.
3. Conserver `TRACK_HISTORY=true` pour les imports incrementaux.
4. Utiliser un dossier destination dedie (ex: `~/Desktop/RAF_selectionnes`).
5. Versionner le fichier de config type, pas les secrets locaux perso.

## Depannage

### `exiftool n'est pas installe`

Installer:

```bash
brew install exiftool
```

### `le dossier source n'existe pas`

Verifier que la carte est montee (`/Volumes/...`) et que `SOURCE_PATH` est correct.

### `aucun fichier ne correspond aux filtres`

Verifier:

- existence des sidecars `.xmp`
- valeurs de `MIN_STARS` et `LABEL`
- test avec `--no-filter`

### Imports lents

Causes possibles:

- verification hash active
- gros volume de fichiers
- support source/destination lent

## Evolution suggeree

- Export CSV/JSON du resume d'import
- Mode verbose avec logs detailles par fichier
- Tests shell automatises (Bats)
- Packaging Homebrew ou script install

## Licence

A definir.

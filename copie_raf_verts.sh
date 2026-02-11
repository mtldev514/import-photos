#!/bin/bash

# =============================================================================
# import-photos
# Outil d'import selectif de fichiers RAW pour workflow photo.
# Lit les metadonnees XMP (etoiles, labels) ecrites par FastRawViewer,
# Photo Mechanic, ou tout autre outil compatible.
# =============================================================================

# === Couleurs ===
VERT='\033[0;32m'
JAUNE='\033[0;33m'
ROUGE='\033[0;31m'
GRIS='\033[0;90m'
CYAN='\033[0;36m'
RESET='\033[0m'

# === Fonction utilitaire : minuscules (compatible macOS bash 3.2) ===
to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# === Valeurs par defaut (avant config) ===
SOURCE_PATH="/Volumes/FujiFilm/DCIM"
DEST_PATH="$HOME/Desktop/RAF_selectionnes"
RAW_EXTENSIONS="RAF"
COPY_JPG=false
MIN_STARS=0
LABEL=""
ORGANIZE_BY_DATE=false
VERIFY_COPY=true
TRACK_HISTORY=true
RECURSIVE=true
DOUBLONS_MODE="ask"
DRY_RUN=false

# === Charger la configuration ===
CONFIG_FILE="$HOME/.import-photos.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# === Aide ===
usage() {
  echo "Usage: import-photos [OPTIONS] [CHEMIN]"
  echo ""
  echo "Import selectif de fichiers RAW bases sur les metadonnees XMP"
  echo "(etoiles, labels couleur) ecrites par FastRawViewer ou autre."
  echo ""
  echo "Arguments:"
  echo "  CHEMIN                     Dossier source (defaut: $SOURCE_PATH)"
  echo ""
  echo "Filtrage:"
  echo "  -s, --stars N              Etoiles minimum, 1-5 (defaut: $MIN_STARS, 0 = desactive)"
  echo "  -l, --label COULEUR        Label couleur: Red, Yellow, Green, Blue, Purple"
  echo "      --no-filter            Importer tous les RAW sans filtrage XMP"
  echo ""
  echo "Destination:"
  echo "  -d, --dest DOSSIER         Dossier de destination (defaut: $DEST_PATH)"
  echo "      --by-date              Organiser en sous-dossiers par date d'import"
  echo ""
  echo "Extensions:"
  echo "  -e, --ext EXT[,EXT,...]    Extensions RAW (defaut: $RAW_EXTENSIONS)"
  echo "      --with-jpg             Copier aussi les JPG correspondants"
  echo ""
  echo "Doublons:"
  echo "  -y, --doublons             Copier les doublons sans demander"
  echo "  -n, --no-doublons          Ignorer les doublons sans demander"
  echo ""
  echo "Securite:"
  echo "      --no-verify            Desactiver la verification d'integrite"
  echo "      --no-history           Ne pas enregistrer l'historique d'import"
  echo ""
  echo "Divers:"
  echo "      --dry-run              Afficher sans copier"
  echo "      --no-recursive         Ne pas chercher dans les sous-dossiers"
  echo "  -h, --help                 Afficher cette aide"
  echo ""
  echo "Exemples:"
  echo "  import-photos                            # Config par defaut"
  echo "  import-photos --stars 3                   # 3 etoiles minimum"
  echo "  import-photos --label Green               # Label vert uniquement"
  echo "  import-photos --stars 1 --label Green     # 1+ etoile ET label vert"
  echo "  import-photos --ext RAF,DNG               # Chercher RAF et DNG"
  echo "  import-photos --with-jpg --by-date        # Avec JPG, tries par date"
  echo "  import-photos --dry-run /Volumes/Autre    # Simuler depuis une autre carte"
  echo ""
  echo "Configuration: $CONFIG_FILE"
  exit 0
}

# === Parsing des options ===
NO_FILTER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -s|--stars)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Erreur: --stars necessite un nombre (1-5)."
        exit 1
      fi
      MIN_STARS="$2"
      shift 2
      ;;
    -l|--label)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Erreur: --label necessite une couleur (Red, Yellow, Green, Blue, Purple)."
        exit 1
      fi
      LABEL="$2"
      shift 2
      ;;
    --no-filter)
      NO_FILTER=true
      shift
      ;;
    -d|--dest)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Erreur: --dest necessite un chemin."
        exit 1
      fi
      DEST_PATH="$2"
      shift 2
      ;;
    --by-date)
      ORGANIZE_BY_DATE=true
      shift
      ;;
    -e|--ext)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Erreur: --ext necessite une ou plusieurs extensions."
        exit 1
      fi
      RAW_EXTENSIONS="$2"
      shift 2
      ;;
    --with-jpg)
      COPY_JPG=true
      shift
      ;;
    -y|--doublons)
      DOUBLONS_MODE="yes"
      shift
      ;;
    -n|--no-doublons)
      DOUBLONS_MODE="no"
      shift
      ;;
    --no-verify)
      VERIFY_COPY=false
      shift
      ;;
    --no-history)
      TRACK_HISTORY=false
      shift
      ;;
    --no-recursive)
      RECURSIVE=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -*)
      echo "Option inconnue: $1"
      echo "Utilisez --help pour voir les options disponibles."
      exit 1
      ;;
    *)
      SOURCE_PATH="$1"
      shift
      ;;
  esac
done

# === Verifications ===
if ! command -v exiftool &>/dev/null; then
  echo -e "${ROUGE}Erreur: exiftool n'est pas installe.${RESET}"
  echo "Installez-le avec: brew install exiftool"
  exit 1
fi

if [ ! -d "$SOURCE_PATH" ]; then
  echo -e "${ROUGE}Erreur: le dossier '$SOURCE_PATH' n'existe pas.${RESET}"
  echo "Verifiez que votre carte SD est bien montee."
  echo ""
  echo "Volumes disponibles:"
  ls /Volumes/ 2>/dev/null
  exit 1
fi

if [ "$MIN_STARS" -eq 0 ] && [ -z "$LABEL" ] && [ "$NO_FILTER" = false ]; then
  echo -e "${JAUNE}Attention: aucun filtre defini (ni etoiles, ni label).${RESET}"
  echo "Utilisez --stars N et/ou --label COULEUR pour filtrer."
  echo "Ou --no-filter pour importer tous les RAW."
  exit 1
fi

# === Initialisation ===
DATE=$(date +%Y%m%d)
DATE_DOSSIER=$(date +%Y-%m-%d)
HISTORY_FILE="$DEST_PATH/.import_history"
MISSING_LOG="$DEST_PATH/manquants_${DATE}.txt"
DOUBLONS=()
COMPTEUR_COPIES=0
COMPTEUR_JPG=0
COMPTEUR_MANQUANTS=0
COMPTEUR_DEJA_IMPORTES=0
COMPTEUR_IGNORES=0
ERREURS_INTEGRITE=0

if [ "$DRY_RUN" = false ]; then
  mkdir -p "$DEST_PATH"
  > "$MISSING_LOG"
  if [ "$TRACK_HISTORY" = true ] && [ ! -f "$HISTORY_FILE" ]; then
    touch "$HISTORY_FILE"
  fi
fi

# Construire le dossier de destination final
if [ "$ORGANIZE_BY_DATE" = true ]; then
  DEST="$DEST_PATH/$DATE_DOSSIER"
  [ "$DRY_RUN" = false ] && mkdir -p "$DEST"
else
  DEST="$DEST_PATH"
fi

# Construire le pattern find pour les extensions
IFS=',' read -ra EXT_ARRAY <<< "$RAW_EXTENSIONS"
FIND_ARGS=()
for i in "${!EXT_ARRAY[@]}"; do
  ext=$(echo "${EXT_ARRAY[$i]}" | xargs)
  if [ $i -gt 0 ]; then
    FIND_ARGS+=("-o")
  fi
  FIND_ARGS+=("-iname" "*.${ext}")
done

# Option recursive ou non
if [ "$RECURSIVE" = true ]; then
  DEPTH_ARGS=()
else
  DEPTH_ARGS=("-maxdepth" "1")
fi

# === Affichage du header ===
echo "=== Import photos - $DATE ==="
echo -e "Source:      ${CYAN}$SOURCE_PATH${RESET}"
echo -e "Destination: ${CYAN}$DEST${RESET}"
echo -n "Filtres:     "
[ "$NO_FILTER" = true ] && echo -n "aucun (tout importer) "
[ "$MIN_STARS" -gt 0 ] && echo -n "etoiles >= $MIN_STARS "
[ -n "$LABEL" ] && echo -n "label = $LABEL "
echo ""
echo -n "Extensions:  "
for ext in "${EXT_ARRAY[@]}"; do echo -n ".$(echo "$ext" | xargs) "; done
[ "$COPY_JPG" = true ] && echo -n "+ .JPG"
echo ""
if [ "$DRY_RUN" = true ]; then
  echo -e "${JAUNE}(Mode dry-run: aucun fichier ne sera copie)${RESET}"
fi
echo ""

# === Construction du cache XMP (un seul appel exiftool) ===
# Cree un fichier temporaire avec les metadonnees de tous les .xmp du dossier
XMP_CACHE=$(mktemp /tmp/import-photos-xmp.XXXXXX)
trap "rm -f '$XMP_CACHE'" EXIT

echo -n "Lecture des metadonnees XMP..."
if [ "$RECURSIVE" = true ]; then
  exiftool -r -p '${Directory}/${FileName}|${Rating}|${Label}' -ext xmp "$SOURCE_PATH" 2>/dev/null > "$XMP_CACHE"
else
  exiftool -p '${Directory}/${FileName}|${Rating}|${Label}' -ext xmp "$SOURCE_PATH" 2>/dev/null > "$XMP_CACHE"
fi
XMP_COUNT=$(wc -l < "$XMP_CACHE" | xargs)
echo " $XMP_COUNT sidecar(s) trouves."
echo ""

# === Fonction : verifier les criteres XMP via le cache ===
check_xmp() {
  local file="$1"
  local base="${file%.*}"
  local sidecar_name="${base}.xmp"

  if [ "$NO_FILTER" = true ]; then
    return 0
  fi

  # Chercher dans le cache (format: chemin.xmp|rating|label)
  local xmp_line=""
  xmp_line=$(grep -F "$(basename "$sidecar_name")" "$XMP_CACHE" | grep -F "$(dirname "$sidecar_name")" | head -1)

  if [ -z "$xmp_line" ]; then
    return 1
  fi

  local rating=""
  local file_label=""
  rating=$(echo "$xmp_line" | cut -d'|' -f2)
  file_label=$(echo "$xmp_line" | cut -d'|' -f3)

  # Verifier les etoiles
  if [ "$MIN_STARS" -gt 0 ]; then
    if [ -z "$rating" ] || [ "$rating" -lt "$MIN_STARS" ] 2>/dev/null; then
      return 1
    fi
  fi

  # Verifier le label (comparaison insensible a la casse)
  if [ -n "$LABEL" ]; then
    local label_lower
    local filter_lower
    label_lower=$(to_lower "$file_label")
    filter_lower=$(to_lower "$LABEL")
    if [ -z "$file_label" ] || [ "$label_lower" != "$filter_lower" ]; then
      return 1
    fi
  fi

  return 0
}

# === Fonction : verifier l'integrite ===
verify_file() {
  local src="$1"
  local dst="$2"

  if [ "$VERIFY_COPY" = false ] || [ "$DRY_RUN" = true ]; then
    return 0
  fi

  local md5_src md5_dst
  md5_src=$(md5 -q "$src" 2>/dev/null || md5sum "$src" 2>/dev/null | awk '{print $1}')
  md5_dst=$(md5 -q "$dst" 2>/dev/null || md5sum "$dst" 2>/dev/null | awk '{print $1}')

  if [ "$md5_src" != "$md5_dst" ]; then
    echo -e "${ROUGE}ERREUR INTEGRITE: $(basename "$dst") - le fichier copie est corrompu!${RESET}"
    rm -f "$dst"
    ((ERREURS_INTEGRITE++))
    return 1
  fi
  return 0
}

# === Fonction : copier un fichier ===
copier_fichier() {
  local src="$1"
  local ext_dest="$2"
  local nom
  nom=$(basename "${src%.*}")
  local dest_file="$DEST/${nom}_${DATE}.${ext_dest}"

  # Deja importe ?
  if [ "$TRACK_HISTORY" = true ] && [ -f "$HISTORY_FILE" ]; then
    local src_id
    src_id=$(stat -f "%m_%z" "$src" 2>/dev/null || stat -c "%Y_%s" "$src" 2>/dev/null)
    local history_key="${nom}_${src_id}"
    if grep -q "^${history_key}$" "$HISTORY_FILE" 2>/dev/null; then
      ((COMPTEUR_DEJA_IMPORTES++))
      return 0
    fi
  fi

  # Doublon dans la destination ?
  if [ -f "$dest_file" ]; then
    DOUBLONS+=("$src|$ext_dest")
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    echo -e "${GRIS}[dry-run] Copierait: ${nom}_${DATE}.${ext_dest}${RESET}"
    ((COMPTEUR_COPIES++))
    return 0
  fi

  if cp "$src" "$dest_file" 2>/dev/null; then
    if verify_file "$src" "$dest_file"; then
      echo -e "${VERT}Copie: ${nom}_${DATE}.${ext_dest}${RESET}"

      # Enregistrer dans l'historique
      if [ "$TRACK_HISTORY" = true ]; then
        local src_id
        src_id=$(stat -f "%m_%z" "$src" 2>/dev/null || stat -c "%Y_%s" "$src" 2>/dev/null)
        echo "${nom}_${src_id}" >> "$HISTORY_FILE"
      fi

      ((COMPTEUR_COPIES++))
    fi
  else
    echo -e "${ROUGE}Erreur de copie: $(basename "$src") (disque plein? permissions?)${RESET}"
    return 1
  fi
}

# === Recherche et import ===
FOUND=false

while IFS= read -r -d '' raw_file; do
  # Verifier les criteres XMP
  if ! check_xmp "$raw_file"; then
    ((COMPTEUR_IGNORES++))
    continue
  fi

  FOUND=true
  raw_ext="${raw_file##*.}"
  copier_fichier "$raw_file" "$raw_ext"

  # Copier le JPG si demande
  if [ "$COPY_JPG" = true ]; then
    local_base="${raw_file%.*}"
    jpg=""
    for jpg_ext in JPG jpg JPEG jpeg; do
      if [ -f "${local_base}.${jpg_ext}" ]; then
        jpg="${local_base}.${jpg_ext}"
        break
      fi
    done
    if [ -n "$jpg" ]; then
      copier_fichier "$jpg" "${jpg##*.}"
      ((COMPTEUR_JPG++))
    fi
  fi

done < <(find "$SOURCE_PATH" "${DEPTH_ARGS[@]}" \( "${FIND_ARGS[@]}" \) -print0 2>/dev/null)

# === Rien trouve ? ===
if [ "$FOUND" = false ]; then
  if [ "$COMPTEUR_IGNORES" -gt 0 ]; then
    echo -e "${JAUNE}$COMPTEUR_IGNORES fichier(s) RAW trouves, mais aucun ne correspond aux filtres.${RESET}"
  else
    echo -e "${JAUNE}Aucun fichier RAW trouve dans $SOURCE_PATH.${RESET}"
  fi
  echo "Verifiez le chemin source et les extensions configurees."
  rm -f "$MISSING_LOG" 2>/dev/null
  exit 0
fi

# === Resume manquants ===
if [ "$DRY_RUN" = false ]; then
  if [ -s "$MISSING_LOG" ]; then
    echo ""
    echo -e "${JAUNE}Fichiers manquants enregistres dans:${RESET}"
    echo "  $MISSING_LOG"
  else
    rm -f "$MISSING_LOG"
  fi
fi

# === Gestion des doublons ===
if [ ${#DOUBLONS[@]} -gt 0 ]; then
  echo ""
  echo -e "${JAUNE}${#DOUBLONS[@]} doublon(s) detecte(s):${RESET}"
  for d in "${DOUBLONS[@]}"; do
    echo "  - $(basename "${d%%|*}")"
  done

  case "$DOUBLONS_MODE" in
    ask)
      echo ""
      read -p "Copier quand meme avec un suffixe? (o/n) " reponse
      [[ "$reponse" =~ ^[oOyY] ]] && DOUBLONS_MODE="yes" || DOUBLONS_MODE="no"
      ;;
  esac

  if [ "$DOUBLONS_MODE" = "yes" ]; then
    for entry in "${DOUBLONS[@]}"; do
      src="${entry%%|*}"
      ext="${entry##*|}"
      nom=$(basename "${src%.*}")
      i=1
      dest_file="$DEST/${nom}_${DATE}_${i}.${ext}"
      while [ -f "$dest_file" ]; do
        ((i++))
        dest_file="$DEST/${nom}_${DATE}_${i}.${ext}"
      done
      if [ "$DRY_RUN" = true ]; then
        echo -e "${GRIS}[dry-run] Copierait: $(basename "$dest_file")${RESET}"
      else
        if cp "$src" "$dest_file" 2>/dev/null; then
          verify_file "$src" "$dest_file"
          echo -e "${VERT}Copie: $(basename "$dest_file")${RESET}"
        else
          echo -e "${ROUGE}Erreur de copie: $(basename "$dest_file")${RESET}"
        fi
      fi
      ((COMPTEUR_COPIES++))
    done
  else
    echo "Doublons ignores."
  fi
fi

# === Resume final ===
echo ""
echo "==============================="
echo "  $COMPTEUR_COPIES fichier(s) copie(s)"
[ "$COPY_JPG" = true ] && [ "$COMPTEUR_JPG" -gt 0 ] && echo "  dont $COMPTEUR_JPG JPG"
[ "$COMPTEUR_DEJA_IMPORTES" -gt 0 ] && echo "  $COMPTEUR_DEJA_IMPORTES deja importe(s) (ignores)"
[ "$COMPTEUR_IGNORES" -gt 0 ] && echo "  $COMPTEUR_IGNORES ne correspondant pas aux filtres"
[ ${#DOUBLONS[@]} -gt 0 ] && echo "  ${#DOUBLONS[@]} doublon(s) detecte(s)"
[ "$ERREURS_INTEGRITE" -gt 0 ] && echo -e "  ${ROUGE}$ERREURS_INTEGRITE erreur(s) d'integrite!${RESET}"
echo "==============================="
echo "Termine."

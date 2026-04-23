#!/bin/bash

# =============================================================================
# import-photos
# Outil d'import selectif de fichiers RAW pour workflow photo.
# Lit les metadonnees XMP (etoiles, labels) ecrites par FastRawViewer,
# Photo Mechanic, ou tout autre outil compatible.
#
# Nommage: {season}_{year}_{mon}_{dd}_{hh}_{mm}_{NNN}.{ext}
# NNN = numero sequentiel dans la minute (001, 002, ...)
# Saisons par solstice: winter (dec21-mar19), spring (mar20-jun20),
#                        summer (jun21-sep21), fall (sep22-dec20)
# L'annee est toujours celle de la prise de vue.
# =============================================================================

# === Couleurs ===
VERT='\033[0;32m'
JAUNE='\033[0;33m'
ROUGE='\033[0;31m'
GRIS='\033[0;90m'
CYAN='\033[0;36m'
RESET='\033[0m'

# === Mois abreges ===
MONTHS=(jan feb mar apr may jun jul aug sep oct nov dec)

# =============================================================================
# Fonctions utilitaires
# =============================================================================

to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

get_season() {
  local month="$1" day="$2"
  case "$month" in
    1|2)  echo "winter" ;;
    3)    [ "$day" -ge 20 ] && echo "spring" || echo "winter" ;;
    4|5)  echo "spring" ;;
    6)    [ "$day" -ge 21 ] && echo "summer" || echo "spring" ;;
    7|8)  echo "summer" ;;
    9)    [ "$day" -ge 22 ] && echo "fall"   || echo "summer" ;;
    10|11) echo "fall" ;;
    12)   [ "$day" -ge 21 ] && echo "winter" || echo "fall" ;;
  esac
}

# Genere le prefixe minute: {season}_{year}_{mon}_{dd}_{hh}_{mm}
# et retourne aussi les secondes pour le tri
generate_minute_prefix() {
  local src="$1"

  local datetime
  datetime=$(exiftool -DateTimeOriginal -s3 "$src" 2>/dev/null)
  if [ -z "$datetime" ]; then
    echo ""
    return 1
  fi

  local year="${datetime:0:4}"
  local month="${datetime:5:2}"
  local day="${datetime:8:2}"
  local hour="${datetime:11:2}"
  local min="${datetime:14:2}"
  local sec="${datetime:17:2}"

  local month_int=$((10#$month))
  local day_int=$((10#$day))
  local mon_name="${MONTHS[$((month_int - 1))]}"
  local season
  season=$(get_season "$month_int" "$day_int")

  echo "${season}_${year}_${mon_name}_${day}_${hour}_${min}|${sec}"
}

# Trouve le prochain numero disponible pour un prefixe minute donne
next_sequence_number() {
  local prefix="$1"
  local ext="$2"
  local n=1

  while [ -f "$DEST_PATH/${prefix}_$(printf '%03d' $n).${ext}" ]; do
    ((n++))
  done
  echo "$n"
}

# =============================================================================
# Fonctions de decision (gates)
# =============================================================================

needs_filter_check() {
  [ "$MIN_STARS" -eq 0 ] && [ -z "$LABEL" ] && [ "$NO_FILTER" = false ]
}

can_clean_source() {
  [ "$CLEAN_SOURCE" = true ] && [ "$COMPTEUR_COPIES" -gt 0 ] && [ "$ERREURS_INTEGRITE" -eq 0 ]
}

clean_blocked_by_errors() {
  [ "$CLEAN_SOURCE" = true ] && [ "$ERREURS_INTEGRITE" -gt 0 ]
}

# =============================================================================
# Fonctions d'action
# =============================================================================

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

check_xmp() {
  local file="$1"
  local base="${file%.*}"
  local sidecar_name="${base}.xmp"

  if [ "$NO_FILTER" = true ]; then
    return 0
  fi

  local xmp_line=""
  xmp_line=$(grep -F "$(basename "$sidecar_name")" "$XMP_CACHE" | grep -F "$(dirname "$sidecar_name")" | head -1)

  if [ -z "$xmp_line" ]; then
    return 1
  fi

  local rating=""
  local file_label=""
  rating=$(echo "$xmp_line" | cut -d'|' -f2)
  file_label=$(echo "$xmp_line" | cut -d'|' -f3)

  if [ "$MIN_STARS" -gt 0 ]; then
    if [ -z "$rating" ] || [ "$rating" -lt "$MIN_STARS" ] 2>/dev/null; then
      return 1
    fi
  fi

  if [ -n "$LABEL" ]; then
    local label_lower filter_lower
    label_lower=$(to_lower "$file_label")
    filter_lower=$(to_lower "$LABEL")
    if [ -z "$file_label" ] || [ "$label_lower" != "$filter_lower" ]; then
      return 1
    fi
  fi

  return 0
}

copier_fichier() {
  local src="$1"
  local ext_dest="$2"
  local ext_lower
  ext_lower=$(to_lower "$ext_dest")

  local result
  result=$(generate_minute_prefix "$src")
  if [ -z "$result" ]; then
    echo -e "${JAUNE}Pas de DateTimeOriginal: $(basename "$src") - ignore${RESET}"
    return 1
  fi

  local prefix="${result%%|*}"
  local seq
  seq=$(next_sequence_number "$prefix" "$ext_lower")
  local new_name="${prefix}_$(printf '%03d' $seq).${ext_lower}"
  local dest_file="$DEST_PATH/$new_name"

  # Verifier si c'est un vrai doublon (meme prefixe minute + meme taille)
  # Chercher parmi les fichiers existants avec ce prefixe
  local src_size
  src_size=$(stat -f "%z" "$src" 2>/dev/null || stat -c "%s" "$src" 2>/dev/null)
  for existing in "$DEST_PATH/${prefix}_"*.${ext_lower}; do
    [ -f "$existing" ] || continue
    local existing_size
    existing_size=$(stat -f "%z" "$existing" 2>/dev/null || stat -c "%s" "$existing" 2>/dev/null)
    if [ "$src_size" = "$existing_size" ]; then
      ((COMPTEUR_DEJA_IMPORTES++))
      return 0
    fi
  done

  if [ "$DRY_RUN" = true ]; then
    echo -e "${GRIS}[dry-run] Copierait: $new_name${RESET}"
    ((COMPTEUR_COPIES++))
    return 0
  fi

  if cp "$src" "$dest_file" 2>/dev/null; then
    if verify_file "$src" "$dest_file"; then
      echo -e "${VERT}Copie: $new_name${RESET}"
      ((COMPTEUR_COPIES++))
    fi
  else
    echo -e "${ROUGE}Erreur de copie: $(basename "$src") (disque plein? permissions?)${RESET}"
    return 1
  fi
}

clean_source() {
  echo -e "${JAUNE}Nettoyage de la source: $SOURCE_PATH${RESET}"
  read -p "Supprimer les fichiers RAW et XMP de la carte? (o/n) " reponse_clean
  if [[ "$reponse_clean" =~ ^[oOyY] ]]; then
    for ext in "${EXT_ARRAY[@]}"; do
      ext=$(echo "$ext" | xargs)
      find "$SOURCE_PATH" "${DEPTH_ARGS[@]}" -iname "*.${ext}" -delete 2>/dev/null
    done
    find "$SOURCE_PATH" "${DEPTH_ARGS[@]}" -iname "*.xmp" -delete 2>/dev/null
    if [ "$COPY_JPG" = true ]; then
      find "$SOURCE_PATH" "${DEPTH_ARGS[@]}" \( -iname "*.jpg" -o -iname "*.jpeg" \) -delete 2>/dev/null
    fi
    echo -e "${VERT}Source nettoyee.${RESET}"
  else
    echo "Nettoyage annule."
  fi
}

print_header() {
  echo "=== Import photos ==="
  echo -e "Source:      ${CYAN}$SOURCE_PATH${RESET}"
  echo -e "Destination: ${CYAN}$DEST_PATH${RESET}"
  echo -n "Filtres:     "
  [ "$NO_FILTER" = true ] && echo -n "aucun (tout importer) "
  [ "$MIN_STARS" -gt 0 ] && echo -n "etoiles >= $MIN_STARS "
  [ -n "$LABEL" ] && echo -n "label = $LABEL "
  echo ""
  echo -n "Extensions:  "
  for ext in "${EXT_ARRAY[@]}"; do echo -n ".$(echo "$ext" | xargs) "; done
  [ "$COPY_JPG" = true ] && echo -n "+ .JPG"
  echo ""
  echo    "Nommage:     {season}_{year}_{mon}_{dd}_{hh}_{mm}_{NNN}.{ext}"
  [ "$CLEAN_SOURCE" = true ] && echo -e "Nettoyage:   ${JAUNE}source sera videe apres import${RESET}"
  if [ "$DRY_RUN" = true ]; then
    echo -e "${JAUNE}(Mode dry-run: aucun fichier ne sera copie)${RESET}"
  fi
  echo ""
}

print_summary() {
  echo ""
  echo "==============================="
  echo "  $COMPTEUR_COPIES fichier(s) copie(s)"
  [ "$COPY_JPG" = true ] && [ "$COMPTEUR_JPG" -gt 0 ] && echo "  dont $COMPTEUR_JPG JPG"
  [ "$COMPTEUR_DEJA_IMPORTES" -gt 0 ] && echo "  $COMPTEUR_DEJA_IMPORTES deja importe(s) (ignores)"
  [ "$COMPTEUR_IGNORES" -gt 0 ] && echo "  $COMPTEUR_IGNORES ne correspondant pas aux filtres"
  [ "$ERREURS_INTEGRITE" -gt 0 ] && echo -e "  ${ROUGE}$ERREURS_INTEGRITE erreur(s) d'integrite!${RESET}"
  echo "==============================="
  echo "Termine."
}

# === Aide ===
usage() {
  echo "Usage: import-photos [OPTIONS] [CHEMIN]"
  echo ""
  echo "Import selectif de fichiers RAW bases sur les metadonnees XMP"
  echo "(etoiles, labels couleur) ecrites par FastRawViewer ou autre."
  echo ""
  echo "Nommage: {season}_{year}_{mon}_{dd}_{hh}_{mm}_{NNN}.{ext}"
  echo "  Ex: winter_2026_feb_10_08_54_001.raf"
  echo "  NNN = numero sequentiel dans la minute"
  echo "  Saisons: winter (dec21-mar19), spring (mar20-jun20),"
  echo "           summer (jun21-sep21), fall (sep22-dec20)"
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
  echo ""
  echo "Extensions:"
  echo "  -e, --ext EXT[,EXT,...]    Extensions RAW (defaut: $RAW_EXTENSIONS)"
  echo "      --with-jpg             Copier aussi les JPG correspondants"
  echo ""
  echo "Post-import:"
  echo "      --clean-source         Supprimer les RAW/XMP de la source apres import"
  echo ""
  echo "Securite:"
  echo "      --no-verify            Desactiver la verification d'integrite"
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
  echo "  import-photos --no-filter                 # Tout importer"
  echo "  import-photos --dry-run /Volumes/Autre    # Simuler depuis une autre carte"
  echo ""
  echo "Configuration: $CONFIG_FILE"
  exit 0
}

# =============================================================================
# Si source par un test, on s'arrete ici (ne pas executer main)
# =============================================================================
if [ "${IMPORT_PHOTOS_TESTING:-}" = true ]; then
  return 0 2>/dev/null || true
fi

# =============================================================================
# Main
# =============================================================================

# === Valeurs par defaut ===
SOURCE_PATH="/Volumes/FujiFilm/DCIM"
DEST_PATH="$HOME/Pictures/fuji-selects"
RAW_EXTENSIONS="RAF"
COPY_JPG=false
MIN_STARS=0
LABEL=""
VERIFY_COPY=true
RECURSIVE=true
DRY_RUN=false
CLEAN_SOURCE=false

# === Charger la configuration ===
CONFIG_FILE="$HOME/.import-photos.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

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
    --no-verify)
      VERIFY_COPY=false
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
    --clean-source)
      CLEAN_SOURCE=true
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

if needs_filter_check; then
  echo -e "${JAUNE}Attention: aucun filtre defini (ni etoiles, ni label).${RESET}"
  echo "Utilisez --stars N et/ou --label COULEUR pour filtrer."
  echo "Ou --no-filter pour importer tous les RAW."
  exit 1
fi

# === Initialisation ===
COMPTEUR_COPIES=0
COMPTEUR_JPG=0
COMPTEUR_DEJA_IMPORTES=0
COMPTEUR_IGNORES=0
ERREURS_INTEGRITE=0

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

# === Import ===
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$DEST_PATH"
fi

print_header

# Construction du cache XMP (un seul appel exiftool)
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

# Recherche et import
FOUND=false

while IFS= read -r -d '' raw_file; do
  if ! check_xmp "$raw_file"; then
    ((COMPTEUR_IGNORES++))
    continue
  fi

  FOUND=true
  raw_ext="${raw_file##*.}"
  copier_fichier "$raw_file" "$raw_ext"

  # Copier le sidecar XMP avec le meme nom
  local_base="${raw_file%.*}"
  if [ -f "${local_base}.xmp" ]; then
    copier_fichier "${local_base}.xmp" "xmp"
  fi

  if [ "$COPY_JPG" = true ]; then
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

# Rien trouve?
if [ "$FOUND" = false ]; then
  if [ "$COMPTEUR_IGNORES" -gt 0 ]; then
    echo -e "${JAUNE}$COMPTEUR_IGNORES fichier(s) RAW trouves, mais aucun ne correspond aux filtres.${RESET}"
  else
    echo -e "${JAUNE}Aucun fichier RAW trouve dans $SOURCE_PATH.${RESET}"
  fi
  echo "Verifiez le chemin source et les extensions configurees."
  exit 0
fi

# === Nettoyage de la source ===
if [ "$CLEAN_SOURCE" = true ]; then
  echo ""
  if clean_blocked_by_errors; then
    echo -e "${ROUGE}Nettoyage annule: $ERREURS_INTEGRITE erreur(s) d'integrite detectee(s).${RESET}"
    echo "Verifiez les fichiers avant de supprimer manuellement."
  elif can_clean_source; then
    if [ "$DRY_RUN" = true ]; then
      echo -e "${JAUNE}[dry-run] Supprimerait les fichiers RAW et XMP de: $SOURCE_PATH${RESET}"
    else
      clean_source
    fi
  fi
fi

# === Resume final ===
print_summary

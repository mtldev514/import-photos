#!/bin/bash

# =============================================================================
# Tests unitaires pour import-photos (copie_raf_verts.sh)
# Usage: bash test_import_photos.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# === Couleurs ===
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# === Helpers ===

assert_true() {
  local label="$1"
  ((TESTS_TOTAL++))
  if eval "$2"; then
    echo -e "  ${C_GREEN}PASS${C_RESET}  $label"
    ((TESTS_PASSED++))
  else
    echo -e "  ${C_RED}FAIL${C_RESET}  $label"
    echo -e "        attendu: true"
    echo -e "        commande: $2"
    ((TESTS_FAILED++))
  fi
}

assert_false() {
  local label="$1"
  ((TESTS_TOTAL++))
  if eval "$2"; then
    echo -e "  ${C_RED}FAIL${C_RESET}  $label"
    echo -e "        attendu: false"
    echo -e "        commande: $2"
    ((TESTS_FAILED++))
  else
    echo -e "  ${C_GREEN}PASS${C_RESET}  $label"
    ((TESTS_PASSED++))
  fi
}

assert_equals() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  ((TESTS_TOTAL++))
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${C_GREEN}PASS${C_RESET}  $label"
    ((TESTS_PASSED++))
  else
    echo -e "  ${C_RED}FAIL${C_RESET}  $label"
    echo -e "        attendu: '$expected'"
    echo -e "        obtenu:  '$actual'"
    ((TESTS_FAILED++))
  fi
}

assert_file_exists() {
  local label="$1"
  local path="$2"
  ((TESTS_TOTAL++))
  if [ -f "$path" ]; then
    echo -e "  ${C_GREEN}PASS${C_RESET}  $label"
    ((TESTS_PASSED++))
  else
    echo -e "  ${C_RED}FAIL${C_RESET}  $label"
    echo -e "        fichier introuvable: $path"
    ((TESTS_FAILED++))
  fi
}

assert_file_not_exists() {
  local label="$1"
  local path="$2"
  ((TESTS_TOTAL++))
  if [ ! -f "$path" ]; then
    echo -e "  ${C_GREEN}PASS${C_RESET}  $label"
    ((TESTS_PASSED++))
  else
    echo -e "  ${C_RED}FAIL${C_RESET}  $label"
    echo -e "        fichier existe mais ne devrait pas: $path"
    ((TESTS_FAILED++))
  fi
}

# Reinitialiser toutes les variables a un etat propre
reset_state() {
  SOURCE_PATH="/tmp/test-import-source"
  DEST_PATH="/tmp/test-import-dest"
  DEST="$DEST_PATH"
  RAW_EXTENSIONS="RAF"
  COPY_JPG=false
  MIN_STARS=0
  LABEL=""
  NO_FILTER=false
  ORGANIZE_BY_DATE=false
  VERIFY_COPY=false  # desactive en test pour eviter md5 lent
  TRACK_HISTORY=false
  RECURSIVE=true
  DOUBLONS_MODE="no"
  DRY_RUN=false
  ARCHIVE_ALL=""
  ARCHIVE_ONLY=false
  CLEAN_SOURCE=false
  COMPTEUR_COPIES=0
  COMPTEUR_JPG=0
  COMPTEUR_MANQUANTS=0
  COMPTEUR_DEJA_IMPORTES=0
  COMPTEUR_IGNORES=0
  ERREURS_INTEGRITE=0
  COMPTEUR_ARCHIVES=0
  ERREURS_ARCHIVE=0
  DOUBLONS=()
  DATE="20260221"
  EXT_ARRAY=("RAF")
  FIND_ARGS=("-iname" "*.RAF")
  DEPTH_ARGS=()
}

# Creer un faux fichier RAF (juste un fichier avec du contenu)
create_fake_raf() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  echo "FAKE_RAF_DATA_$(basename "$path")" > "$path"
}

# Creer un faux sidecar XMP dans le cache
create_xmp_cache_entry() {
  local xmp_path="$1"
  local rating="$2"
  local label="$3"
  echo "${xmp_path}|${rating}|${label}" >> "$XMP_CACHE"
}

# Nettoyer les dossiers de test
cleanup() {
  rm -rf /tmp/test-import-source /tmp/test-import-dest /tmp/test-import-archive
  rm -f /tmp/test-xmp-cache.*
}

# Charger les fonctions du script (sans executer main)
IMPORT_PHOTOS_TESTING=true
source "$SCRIPT_DIR/copie_raf_verts.sh"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: should_run_import ===${C_RESET}"
# =============================================================================

reset_state
ARCHIVE_ONLY=false
assert_true "import actif par defaut" "should_run_import"

reset_state
ARCHIVE_ONLY=true
assert_false "import desactive avec archive-only" "should_run_import"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: should_run_archive ===${C_RESET}"
# =============================================================================

reset_state
ARCHIVE_ALL=""
assert_false "archive desactive par defaut" "should_run_archive"

reset_state
ARCHIVE_ALL="/tmp/test-archive"
assert_true "archive actif quand chemin defini" "should_run_archive"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: needs_filter_check ===${C_RESET}"
# =============================================================================

reset_state
ARCHIVE_ONLY=false
MIN_STARS=0
LABEL=""
NO_FILTER=false
assert_true "filtre requis sans etoiles ni label" "needs_filter_check"

reset_state
MIN_STARS=3
assert_false "filtre non requis avec etoiles" "needs_filter_check"

reset_state
LABEL="Green"
assert_false "filtre non requis avec label" "needs_filter_check"

reset_state
NO_FILTER=true
assert_false "filtre non requis avec --no-filter" "needs_filter_check"

reset_state
ARCHIVE_ONLY=true
MIN_STARS=0
LABEL=""
NO_FILTER=false
assert_false "filtre non requis en archive-only" "needs_filter_check"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: needs_exiftool ===${C_RESET}"
# =============================================================================

reset_state
ARCHIVE_ONLY=false
assert_true "exiftool requis pour import" "needs_exiftool"

reset_state
ARCHIVE_ONLY=true
assert_false "exiftool non requis pour archive-only" "needs_exiftool"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: can_clean_source ===${C_RESET}"
# =============================================================================

reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=5
COMPTEUR_ARCHIVES=0
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=0
assert_true "nettoyage autorise: copies ok, zero erreurs" "can_clean_source"

reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=0
COMPTEUR_ARCHIVES=10
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=0
assert_true "nettoyage autorise: archives ok, zero erreurs" "can_clean_source"

reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=5
ERREURS_INTEGRITE=1
ERREURS_ARCHIVE=0
assert_false "nettoyage bloque: erreurs integrite" "can_clean_source"

reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=5
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=2
assert_false "nettoyage bloque: erreurs archive" "can_clean_source"

reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=0
COMPTEUR_ARCHIVES=0
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=0
assert_false "nettoyage bloque: zero fichiers traites" "can_clean_source"

reset_state
CLEAN_SOURCE=false
COMPTEUR_COPIES=5
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=0
assert_false "nettoyage bloque: non demande" "can_clean_source"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: clean_blocked_by_errors ===${C_RESET}"
# =============================================================================

reset_state
CLEAN_SOURCE=true
ERREURS_INTEGRITE=1
ERREURS_ARCHIVE=0
assert_true "bloque par erreurs integrite" "clean_blocked_by_errors"

reset_state
CLEAN_SOURCE=true
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=3
assert_true "bloque par erreurs archive" "clean_blocked_by_errors"

reset_state
CLEAN_SOURCE=true
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=0
assert_false "pas bloque sans erreurs" "clean_blocked_by_errors"

reset_state
CLEAN_SOURCE=false
ERREURS_INTEGRITE=5
ERREURS_ARCHIVE=0
assert_false "pas bloque si clean non demande" "clean_blocked_by_errors"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: to_lower ===${C_RESET}"
# =============================================================================

assert_equals "minuscules depuis majuscules" "green" "$(to_lower 'GREEN')"
assert_equals "minuscules depuis mixed" "red" "$(to_lower 'Red')"
assert_equals "deja en minuscules" "blue" "$(to_lower 'blue')"
assert_equals "chaine vide" "" "$(to_lower '')"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: check_xmp ===${C_RESET}"
# =============================================================================

cleanup
reset_state
XMP_CACHE=$(mktemp /tmp/test-xmp-cache.XXXXXX)

# Creer des entrees dans le cache
mkdir -p /tmp/test-import-source/DCIM
create_xmp_cache_entry "/tmp/test-import-source/DCIM/DSCF0001.xmp" "3" "Green"
create_xmp_cache_entry "/tmp/test-import-source/DCIM/DSCF0002.xmp" "1" "Red"
create_xmp_cache_entry "/tmp/test-import-source/DCIM/DSCF0003.xmp" "" ""

MIN_STARS=0
LABEL=""
NO_FILTER=false

# Sans filtre = pas de match (car pas no-filter et pas de critere)
# Avec no-filter, tout passe
NO_FILTER=true
assert_true "no-filter: tout passe" "check_xmp '/tmp/test-import-source/DCIM/DSCF0001.RAF'"
assert_true "no-filter: meme sans XMP" "check_xmp '/tmp/test-import-source/DCIM/INEXISTANT.RAF'"

# Filtre par etoiles
NO_FILTER=false
MIN_STARS=2
LABEL=""
assert_true "3 etoiles >= 2 min" "check_xmp '/tmp/test-import-source/DCIM/DSCF0001.RAF'"
assert_false "1 etoile < 2 min" "check_xmp '/tmp/test-import-source/DCIM/DSCF0002.RAF'"
assert_false "pas de rating < 2 min" "check_xmp '/tmp/test-import-source/DCIM/DSCF0003.RAF'"

# Filtre par label
MIN_STARS=0
LABEL="Green"
assert_true "label Green match Green" "check_xmp '/tmp/test-import-source/DCIM/DSCF0001.RAF'"
assert_false "label Green ne match pas Red" "check_xmp '/tmp/test-import-source/DCIM/DSCF0002.RAF'"

# Filtre combine
MIN_STARS=2
LABEL="Green"
assert_true "3 etoiles + Green = match" "check_xmp '/tmp/test-import-source/DCIM/DSCF0001.RAF'"
assert_false "1 etoile + Red = pas de match" "check_xmp '/tmp/test-import-source/DCIM/DSCF0002.RAF'"

# Label insensible a la casse
MIN_STARS=0
LABEL="green"
assert_true "label insensible a la casse" "check_xmp '/tmp/test-import-source/DCIM/DSCF0001.RAF'"

# Fichier sans XMP
MIN_STARS=1
LABEL=""
assert_false "fichier sans sidecar XMP" "check_xmp '/tmp/test-import-source/DCIM/INEXISTANT.RAF'"

rm -f "$XMP_CACHE"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: verify_file ===${C_RESET}"
# =============================================================================

cleanup
reset_state
mkdir -p /tmp/test-import-source /tmp/test-import-dest

# Verification desactivee
VERIFY_COPY=false
echo "contenu" > /tmp/test-import-source/a.txt
echo "different" > /tmp/test-import-dest/a.txt
assert_true "verification desactivee = toujours ok" \
  "verify_file /tmp/test-import-source/a.txt /tmp/test-import-dest/a.txt"

# Verification en dry-run
VERIFY_COPY=true
DRY_RUN=true
assert_true "dry-run = toujours ok" \
  "verify_file /tmp/test-import-source/a.txt /tmp/test-import-dest/a.txt"

# Verification reelle: fichiers identiques
DRY_RUN=false
VERIFY_COPY=true
ERREURS_INTEGRITE=0
echo "meme_contenu" > /tmp/test-import-source/b.txt
cp /tmp/test-import-source/b.txt /tmp/test-import-dest/b.txt
assert_true "fichiers identiques = ok" \
  "verify_file /tmp/test-import-source/b.txt /tmp/test-import-dest/b.txt"
assert_equals "zero erreurs apres verif ok" "0" "$ERREURS_INTEGRITE"

# Verification reelle: fichiers differents
echo "contenu_a" > /tmp/test-import-source/c.txt
echo "contenu_b" > /tmp/test-import-dest/c.txt
ERREURS_INTEGRITE=0
assert_false "fichiers differents = erreur" \
  "verify_file /tmp/test-import-source/c.txt /tmp/test-import-dest/c.txt"
assert_equals "erreur incrementee apres corruption" "1" "$ERREURS_INTEGRITE"
assert_file_not_exists "fichier corrompu supprime" "/tmp/test-import-dest/c.txt"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: copier_fichier ===${C_RESET}"
# =============================================================================

cleanup
reset_state
mkdir -p /tmp/test-import-source /tmp/test-import-dest
DEST="/tmp/test-import-dest"

create_fake_raf /tmp/test-import-source/DSCF0001.RAF
copier_fichier /tmp/test-import-source/DSCF0001.RAF "RAF" > /dev/null 2>&1
assert_file_exists "fichier copie avec suffixe date" "/tmp/test-import-dest/DSCF0001_${DATE}.RAF"
assert_equals "compteur incremente" "1" "$COMPTEUR_COPIES"

# Doublon
DOUBLONS=()
copier_fichier /tmp/test-import-source/DSCF0001.RAF "RAF" > /dev/null 2>&1
assert_equals "doublon detecte" "1" "${#DOUBLONS[@]}"

# Dry-run
cleanup
reset_state
DRY_RUN=true
DEST="/tmp/test-import-dest"
create_fake_raf /tmp/test-import-source/DSCF0099.RAF
copier_fichier /tmp/test-import-source/DSCF0099.RAF "RAF" > /dev/null 2>&1
assert_file_not_exists "dry-run ne copie pas" "/tmp/test-import-dest/DSCF0099_${DATE}.RAF"
assert_equals "compteur incremente en dry-run" "1" "$COMPTEUR_COPIES"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: archiver_fichier ===${C_RESET}"
# =============================================================================

cleanup
reset_state
ARCHIVE_ALL="/tmp/test-import-archive"
mkdir -p /tmp/test-import-source "$ARCHIVE_ALL"

create_fake_raf /tmp/test-import-source/DSCF0010.RAF
archiver_fichier /tmp/test-import-source/DSCF0010.RAF > /dev/null 2>&1
assert_file_exists "fichier archive" "/tmp/test-import-archive/DSCF0010_${DATE}.RAF"
assert_equals "compteur archives incremente" "1" "$COMPTEUR_ARCHIVES"

# Doublon dans l'archive: suffixe _1
create_fake_raf /tmp/test-import-source/DSCF0010.RAF
archiver_fichier /tmp/test-import-source/DSCF0010.RAF > /dev/null 2>&1
assert_file_exists "doublon archive avec suffixe _1" "/tmp/test-import-archive/DSCF0010_${DATE}_1.RAF"
assert_equals "compteur archives = 2" "2" "$COMPTEUR_ARCHIVES"

# Dry-run
cleanup
reset_state
ARCHIVE_ALL="/tmp/test-import-archive"
DRY_RUN=true
mkdir -p /tmp/test-import-source
create_fake_raf /tmp/test-import-source/DSCF0020.RAF
archiver_fichier /tmp/test-import-source/DSCF0020.RAF > /dev/null 2>&1
assert_file_not_exists "dry-run n'archive pas" "/tmp/test-import-archive/DSCF0020_${DATE}.RAF"
assert_equals "compteur incremente en dry-run" "1" "$COMPTEUR_ARCHIVES"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: combinaisons de modes ===${C_RESET}"
# =============================================================================

# archive-only active archive ET desactive import
reset_state
ARCHIVE_ONLY=true
ARCHIVE_ALL="/tmp/somewhere"
assert_false "archive-only desactive import" "should_run_import"
assert_true "archive-only active archive" "should_run_archive"

# import + archive-all
reset_state
ARCHIVE_ONLY=false
ARCHIVE_ALL="/tmp/somewhere"
assert_true "import + archive: import actif" "should_run_import"
assert_true "import + archive: archive actif" "should_run_archive"

# import seul
reset_state
ARCHIVE_ONLY=false
ARCHIVE_ALL=""
assert_true "import seul: import actif" "should_run_import"
assert_false "import seul: archive inactif" "should_run_archive"

# =============================================================================
echo ""
echo -e "${C_CYAN}=== Tests: clean safety avec les deux phases ===${C_RESET}"
# =============================================================================

# Copies ok + archives ok = clean autorise
reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=3
COMPTEUR_ARCHIVES=10
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=0
assert_true "clean ok quand import + archive reussis" "can_clean_source"

# Copies ok + erreurs archive = clean bloque
reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=3
COMPTEUR_ARCHIVES=8
ERREURS_INTEGRITE=0
ERREURS_ARCHIVE=2
assert_false "clean bloque par erreurs archive" "can_clean_source"
assert_true "erreurs archive bloquent" "clean_blocked_by_errors"

# Erreurs import + archives ok = clean bloque
reset_state
CLEAN_SOURCE=true
COMPTEUR_COPIES=4
COMPTEUR_ARCHIVES=10
ERREURS_INTEGRITE=1
ERREURS_ARCHIVE=0
assert_false "clean bloque par erreurs import" "can_clean_source"
assert_true "erreurs import bloquent" "clean_blocked_by_errors"

# =============================================================================
# Resume
# =============================================================================

cleanup

echo ""
echo "==============================="
if [ "$TESTS_FAILED" -eq 0 ]; then
  echo -e "  ${C_GREEN}$TESTS_PASSED/$TESTS_TOTAL tests passes${C_RESET}"
else
  echo -e "  ${C_GREEN}$TESTS_PASSED passes${C_RESET}, ${C_RED}$TESTS_FAILED echoues${C_RESET} / $TESTS_TOTAL total"
fi
echo "==============================="

exit "$TESTS_FAILED"

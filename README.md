# import-photos

Selective RAW import from SD card based on XMP metadata (stars, color labels) written by FastRawViewer, Photo Mechanic, or similar.

## Naming convention

Files are renamed on import using EXIF data:

```
{season}_{year}_{mon}_{dd}_{hh}_{mm}_{NNN}.{ext}
```

Example: `winter_2026_feb_10_08_54_001.raf`

- **NNN** — sequential number within the minute (001, 002, ...)
- **Seasons** — astronomical, by solstice: winter (dec 21–mar 19), spring (mar 20–jun 20), summer (jun 21–sep 21), fall (sep 22–dec 20)
- **Year** — always the year the photo was taken
- Destination is flat (no subfolders)

## Workflow

1. Shoot with Fuji X-T5
2. Rate/label RAFs on the SD card in FastRawViewer
3. Run `import-photos` — only selected files get imported with clean names
4. SD card stays as backup until you format it

## Prerequisites

```bash
brew install exiftool
```

## Setup

The script is aliased in `.zshrc`:

```bash
alias import-photos="~/Developer/prototypes/import-photos/copie_raf_verts.sh"
```

Config is loaded from `~/.import-photos.conf` (copy `import-photos.conf` as a starting point).

## Usage

```bash
# Dry-run first (always)
import-photos --dry-run --label Green

# Import green-labeled RAFs
import-photos --label Green

# Import 3+ stars
import-photos --stars 3

# Import everything (no XMP filter)
import-photos --no-filter

# Custom source
import-photos --dry-run /Volumes/OtherCard/DCIM
```

## Options

| Flag | Description |
|------|-------------|
| `-s, --stars N` | Minimum star rating (1–5) |
| `-l, --label COLOR` | Color label: Red, Yellow, Green, Blue, Purple |
| `--no-filter` | Import all RAFs without XMP filtering |
| `-d, --dest DIR` | Destination (default: `~/Pictures/fuji-selects`) |
| `-e, --ext EXT` | Extensions, comma-separated (default: RAF) |
| `--with-jpg` | Also copy matching JPGs |
| `--clean-source` | Delete RAW/XMP from card after successful import |
| `--no-verify` | Skip MD5 integrity check |
| `--dry-run` | Preview without copying |
| `--no-recursive` | Don't search subdirectories |
| `-h, --help` | Full help |

## Duplicate handling

Same photo imported twice produces the same deterministic filename. If a file with the same name and size already exists, it's skipped. If same name but different size (burst), it gets the next sequence number (`_002`, `_003`).

## See also

- [`rename-photos`](../rename-photos/) — standalone rename tool for existing photo folders

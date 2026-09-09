# Helium Profile Shortcuts for GNOME

A command-line automation script to create, manage, and remove individual GNOME application shortcuts (`.desktop` launchers) for [Helium Browser](https://github.com/imputnet/helium) profiles with custom HTML color codes, suggested color palettes, and profile badge icons.

Each profile gets its own distinct launcher in GNOME's Application Overview and search (e.g. `Helium (Personal)`, `Helium (Work)`), a custom-colored branded Helium icon, optional pinning to GNOME Dash/Dock favorites, and optional placement on `~/Desktop`.

---

## Overview & Upstream References

- **Upstream Browser**: [Helium Browser (`net.imput.helium`)](https://github.com/imputnet/helium)
- **Desktop Entry Specification**: [FreeDesktop.org Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- **Icon Theme Specification**: [FreeDesktop Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/)
- **GNOME Shell Integration**: Seamless integration with `~/.local/share/applications`, `~/.local/share/icons/hicolor`, and `org.gnome.shell favorite-apps`.

---

## Prerequisites

- **Operating System**: Linux with GNOME Shell (or any FreeDesktop-compliant desktop environment)
- **Helium Browser**: `helium-browser` installed on PATH
- **jq**: For parsing Chromium profile state (`Local State`)
- **Python 3**: For SVG generation, color shade computation, and GNOME GSettings array manipulation
- **librsvg / rsvg-convert** (optional): For rasterizing 128x128 PNG fallback icons alongside SVGs
- **desktop-file-utils** (optional): For updating the desktop database (`update-desktop-database`)

---

## Quick Start

1. **List all detected profiles, shortcut status, and icon colors**:
   ```bash
   ./manage-shortcuts.sh list
   ```

2. **Interactive shortcut creation** (presents color palette with live terminal swatches):
   ```bash
   ./manage-shortcuts.sh create "PC"
   ```

3. **Create shortcut with specific HTML hex color code**:
   ```bash
   ./manage-shortcuts.sh create "PC" --color "#FF5733"
   ```

4. **Create shortcut using palette number or color name**:
   ```bash
   ./manage-shortcuts.sh create "PC" --color 2 --pin        # 2 = Teal (#00a896)
   ./manage-shortcuts.sh create "PC" --color teal --pin
   ```

5. **Create shortcuts for ALL profiles** (automatically assigns distinct palette colors):
   ```bash
   ./manage-shortcuts.sh create --all --pin
   ```

6. **Remove shortcut and clean up custom icons**:
   ```bash
   ./manage-shortcuts.sh remove "PC"
   ```

---

## Color Selection & Palettes

When creating a shortcut without `--color` in a terminal, the script presents an interactive menu with 24-bit truecolor terminal swatches:

```text
==> Select an icon color for profile 'PC':
   1) [  ] Blue         (#3584e4)
   2) [  ] Teal         (#00a896)
   3) [  ] Green        (#33d17a)
   4) [  ] Yellow       (#f6d32d)
   5) [  ] Orange       (#ff7800)
   6) [  ] Red          (#e01b24)
   7) [  ] Purple       (#9141ac)
   8) [  ] Pink         (#e83e8c)
   9) [  ] Slate        (#3d3846)
  10) [  ] Cyan         (#17a2b8)
   c)  Custom HTML / Hex color code (e.g. #FF5733, teal, #8A2BE2)

Choose a color [1-10, c, or #hex] (default: 1): 
```

### Supported Color Inputs
- **Palette Number**: `1` through `10`
- **Full 6-Digit Hex**: `#3584e4` or `3584e4`
- **Short 3-Digit Hex**: `#f00` (expands to `#ff0000`)
- **HTML Color Names**: `blue`, `teal`, `green`, `yellow`, `orange`, `red`, `purple`, `pink`, `slate`, `cyan`, `gold`, `coral`, `indigo`, `emerald`, `amber`, `rose`, `violet`, `sky`
- **Custom Prompt**: Type `c` or `custom` to enter an arbitrary HTML color code

---

---

## Shortcut Title Customization

By default, shortcuts are titled:
`Helium (<Profile Display Name>)` (e.g. `Helium (PC)` or `Helium (You)`).

You have full control over the title:

1. **Interactive Prompt**:
   When creating a shortcut without `--title`, the script prompts for a custom title and shows the default:
   ```text
   ==> Shortcut Title:
   Enter shortcut title [default: 'Helium (PC)']: 
   ```
   Pressing <kbd>Enter</kbd> keeps the default title, or you can enter any custom string.

2. **Explicit Title Flag**:
   Use `-t, --title <title>` (or `-n, --name <title>`):
   ```bash
   ./manage-shortcuts.sh create "PC" --title "Work & Research Browser"
   ```

3. **Batch Title Templates (`--title-format`)**:
   When using `--all`, use `--title-format` with placeholders `{name}` and `{profile}`:
   ```bash
   ./manage-shortcuts.sh create --all --title-format "Helium - {name}"
   # Result: "Helium - PC", "Helium - You"

   ./manage-shortcuts.sh create --all --title-format "{name} Browser"
   # Result: "PC Browser", "You Browser"
   ```

---

## CLI Options & Flags

```text
Usage: ./manage-shortcuts.sh <command> [options] [profile_name_or_dir]

Commands:
  list, -l                  List all detected Helium profiles, shortcut titles, and icon colors
  create, add, -c           Create GNOME shortcut (.desktop) for a profile with custom title & color
  remove, rm, -r            Remove GNOME shortcut (.desktop) and custom icon for a profile
  help, -h                  Display this help message

Options for 'create':
  -a, --all                 Create shortcuts for all detected profiles
  -t, --title <title>       Custom title for the shortcut (e.g. "Work Browser", "Helium - PC")
  -n, --name <name>         Alias for --title
      --title-format <fmt>  Title format template for shortcuts (default: "Helium ({name})")
                            Supports placeholders: {name} and {profile}
  -C, --color <code>        HTML/hex color code (e.g. #3584E4), color name (e.g. teal),
                            or palette number (1-10) for the icon
      --no-badge            Omit the profile initial letter badge on the icon
      --default-icon        Use standard system helium-browser icon without custom color
  -i, --icon <path|name>    Use an explicit custom icon file or theme name instead of generated color
      --pin, --favorite     Pin shortcut to GNOME Dash / Favorites
      --desktop             Also place shortcut in ~/Desktop
      --non-interactive     Do not prompt interactively for title or color; use defaults or flags
      --dry-run             Display generated .desktop and icon details without writing

Options for 'remove':
  -a, --all                 Remove shortcuts and custom icons for all profiles
      --dry-run             Show files that would be removed without deleting

General Options:
      --config-dir <path>   Helium config directory (default: auto-detect ~/.config/net.imput.helium)
      --binary <path>       Helium executable binary/command (default: helium-browser)
  -h, --help                Show this help message
```

---

## Usage Examples

### 1. Discover Profiles and View Icon Colors
```bash
./manage-shortcuts.sh list
```
Output:
```text
==> Helium Configuration Directory: /home/jkotra/.config/net.imput.helium

==> Detected Helium Profiles & Shortcut Status:
  DIRECTORY    DISPLAY NAME   DESKTOP ENTRY                      STATUS     ICON COLOR       FAVORITE
  ---------    ------------   -------------                      ------     ----------       --------
  Default      You            helium-profile-default.desktop     Not Found      Default     No      
  Profile 1    PC             helium-profile-profile-1.desktop   Installed       #33d17a     No      
```

### 2. Create Shortcut with Custom Hex Color and Pin to Dash
```bash
./manage-shortcuts.sh create "PC" --color "#33d17a" --pin
```

### 3. Create Shortcut Without Initial Letter Badge
```bash
./manage-shortcuts.sh create "Profile 1" --color "#9141ac" --no-badge
```

### 4. Create Shortcuts for All Profiles with Distinct Colors
```bash
./manage-shortcuts.sh create --all --pin
```

### 5. Preview Generated Entry and Icon Without Modifying Files
```bash
./manage-shortcuts.sh create "PC" --color "#e01b24" --dry-run
```

### 6. Remove Shortcut and Delete Generated Icons
```bash
./manage-shortcuts.sh remove "PC"
```

### 7. Remove All Profile Shortcuts and Icons
```bash
./manage-shortcuts.sh remove --all
```

---

## Technical Details & Architecture

### Profile Discovery
Helium stores global profile metadata in JSON format at `${XDG_CONFIG_HOME}/net.imput.helium/Local State`. The script uses `jq` to query `.profile.info_cache`:
- Profile folder name (e.g. `Default`, `Profile 1`)
- Custom user-assigned profile name (e.g. `You`, `PC`)

### Custom Icon Generation
When a color code is selected:
1. Shading Math: Computes multi-tone lighting, dark undertones, and drop shadows from the base HTML hex code.
2. SVG Generation: Constructs a scalable SVG icon matching GNOME's Adwaita design language with:
   - Curved baseplate and elevation shadow
   - Helium asterisk/star emblem in white
   - Contrasting bottom-right emblem badge displaying the profile's initial letter
   - Embedded `data-color` attribute so `list` can read and display the color swatch
3. Target Locations:
   - Scalable: `~/.local/share/icons/hicolor/scalable/apps/helium-profile-<slug>.svg`
   - Raster (128x128): `~/.local/share/icons/hicolor/128x128/apps/helium-profile-<slug>.png`

### Desktop Launcher Generation
Each shortcut is generated in `${XDG_DATA_HOME:-~/.local/share}/applications/` following the naming pattern:
`helium-profile-<slug>.desktop`

The launcher includes:
- Command: `helium-browser --profile-directory="<Profile Dir>" %U`
- Direct path to the custom colored icon
- Standard MIME types and web browser categories
- Quick actions for **New Window** and **New Incognito Window** scoped to that specific profile
- Execution permission bits and immediate desktop database registration via `update-desktop-database` and `gtk-update-icon-cache`

### GNOME Dash Pinning
When `--pin` is provided, the script safely interacts with the `org.gnome.shell favorite-apps` GSettings schema via Python, appending the `.desktop` basename if not already present. When removing shortcuts, any pinned references and generated icon files are automatically cleaned up.

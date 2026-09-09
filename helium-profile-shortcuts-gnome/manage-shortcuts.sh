#!/usr/bin/env bash
# ==============================================================================
# Script: manage-shortcuts.sh
# Description: Create, list, and remove GNOME shortcuts (.desktop files)
#              for Helium Browser profiles with customizable titles and
#              custom HTML color codes.
#              Provides suggested color palette, allows custom hex codes,
#              generates tailored high-resolution SVG and PNG icons,
#              and supports GNOME dash/favorites pinning and ~/Desktop shortcuts.
#
# Upstream: https://github.com/imputnet/helium
# ==============================================================================

set -euo pipefail

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

print_step() {
    echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"
}

# Resolve default directories
HELIUM_BIN="${HELIUM_BIN:-helium-browser}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="${XDG_DATA_HOME}/applications"
ICONS_SCALABLE_DIR="${XDG_DATA_HOME}/icons/hicolor/scalable/apps"
ICONS_128_DIR="${XDG_DATA_HOME}/icons/hicolor/128x128/apps"
DESKTOP_DIR="${HOME}/Desktop"

# Suggested Palette: Name : Hex
SUGGESTED_COLORS=(
    "Blue:#3584e4"
    "Teal:#00a896"
    "Green:#33d17a"
    "Yellow:#f6d32d"
    "Orange:#ff7800"
    "Red:#e01b24"
    "Purple:#9141ac"
    "Pink:#e83e8c"
    "Slate:#3d3846"
    "Cyan:#17a2b8"
)

# Find Helium config directory
detect_helium_config_dir() {
    local candidates=(
        "${XDG_CONFIG_HOME}/net.imput.helium"
        "${XDG_CONFIG_HOME}/helium"
        "${XDG_CONFIG_HOME}/helium-browser"
    )
    for dir in "${candidates[@]}"; do
        if [ -d "$dir" ]; then
            echo "$dir"
            return 0
        fi
    done
    echo "${XDG_CONFIG_HOME}/net.imput.helium"
}

CONFIG_DIR=""
CUSTOM_TITLE=""
TITLE_FORMAT="Helium ({name})"
CUSTOM_ICON=""
CHOSEN_COLOR=""
WITH_BADGE="true"
NO_COLOR="false"
NON_INTERACTIVE="false"
PIN_FAVORITE="false"
ADD_DESKTOP="false"
DRY_RUN="false"
PROCESS_ALL="false"

usage() {
    cat << 'EOF'
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

Title Customization:
  Default title: "Helium (<Profile Display Name>)"  (e.g. "Helium (PC)", "Helium (You)")
  
  When run interactively without --title, the script prompts you to customize the title
  or press Enter to keep the default.

  For automated batches with --all, use --title-format:
    --title-format "{name} Browser"   -> "PC Browser", "You Browser"
    --title-format "Helium - {name}"  -> "Helium - PC", "Helium - You"

Examples:
  # 1. Interactive creation (prompts for title & color selection with live swatches)
  ./manage-shortcuts.sh create "PC"

  # 2. Create shortcut with custom title and hex color code
  ./manage-shortcuts.sh create "PC" --title "Helium - Work" --color "#FF5733"

  # 3. Create shortcut with custom title and pin to GNOME Dash
  ./manage-shortcuts.sh create "PC" --title "Daily Driver" --color teal --pin

  # 4. Create shortcuts for ALL profiles using a custom title format
  ./manage-shortcuts.sh create --all --title-format "Helium - {name}" --pin

  # 5. List all profiles, current shortcut titles, and icon colors
  ./manage-shortcuts.sh list

  # 6. Remove shortcut and delete generated custom icons
  ./manage-shortcuts.sh remove "PC"
EOF
}

check_dependencies() {
    if ! command -v jq &>/dev/null; then
        print_error "'jq' is required to parse Helium profile data. Please install jq."
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        print_error "'python3' is required for icon and configuration generation."
        exit 1
    fi
}

slugify() {
    local input="$1"
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g'
}

print_color_swatch() {
    local hex="$1"
    if [[ "$hex" =~ ^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]]; then
        local r=$((16#${BASH_REMATCH[1]}))
        local g=$((16#${BASH_REMATCH[2]}))
        local b=$((16#${BASH_REMATCH[3]}))
        printf "\033[48;2;%d;%d;%dm    \033[0m" "$r" "$g" "$b"
    else
        printf "    "
    fi
}

normalize_color() {
    local raw_color="$1"
    python3 -c "
import sys

raw = sys.argv[1].strip()

palette = [
    '#3584e4', '#00a896', '#33d17a', '#f6d32d', '#ff7800',
    '#e01b24', '#9141ac', '#e83e8c', '#3d3846', '#17a2b8'
]
if raw.isdigit():
    idx = int(raw) - 1
    if 0 <= idx < len(palette):
        print(palette[idx])
        sys.exit(0)

named = {
    'blue': '#3584e4', 'teal': '#00a896', 'green': '#33d17a', 'yellow': '#f6d32d',
    'orange': '#ff7800', 'red': '#e01b24', 'purple': '#9141ac', 'pink': '#e83e8c',
    'slate': '#3d3846', 'cyan': '#17a2b8', 'gold': '#f5c211', 'coral': '#f87171',
    'white': '#ffffff', 'black': '#242424', 'indigo': '#4f46e5', 'emerald': '#10b981',
    'amber': '#f59e0b', 'rose': '#f43f5e', 'violet': '#8b5cf6', 'sky': '#0ea5e9'
}

low = raw.lower()
if low in named:
    print(named[low])
    sys.exit(0)

if not raw.startswith('#'):
    raw = '#' + raw

if len(raw) == 4: # #rgb -> #rrggbb
    raw = '#' + ''.join([c*2 for c in raw[1:]])

if len(raw) == 7:
    try:
        int(raw[1:], 16)
        print(raw.lower())
        sys.exit(0)
    except ValueError:
        pass

sys.exit(1)
" "$raw_color" 2>/dev/null || echo ""
}

# Prompt for shortcut title.
# ALL prompts and UI are redirected to stderr (>&2) so that command substitution
# captures only the sanitized title.
prompt_title_selection() {
    local default_title="$1"
    local user_input=""

    echo "" >&2
    echo -e "${BOLD}${CYAN}==>${NC} ${BOLD}Shortcut Title:${NC}" >&2
    read -r -p "Enter shortcut title [default: '${default_title}']: " user_input </dev/tty || user_input=""
    
    # Strip carriage returns, newlines, and trim leading/trailing whitespace
    user_input=$(echo "$user_input" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    if [ -n "$user_input" ]; then
        echo "$user_input"
    else
        echo "$default_title"
    fi
}

# Prompt for shortcut icon color.
# ALL prompts and UI are redirected to stderr (>&2) so that command substitution
# captures only the normalized hex code.
prompt_color_selection() {
    local profile_display_name="$1"

    echo "" >&2
    echo -e "${BOLD}${CYAN}==>${NC} ${BOLD}Select an icon color for profile '${profile_display_name}':${NC}" >&2
    local idx=1
    for entry in "${SUGGESTED_COLORS[@]}"; do
        local name="${entry%%:*}"
        local hex="${entry##*:}"
        local swatch
        swatch=$(print_color_swatch "$hex")
        printf "  %2d) %s  %-12s (%s)\n" "$idx" "$swatch" "$name" "$hex" >&2
        idx=$((idx + 1))
    done
    echo -e "   c)  Custom HTML / Hex color code (e.g. #FF5733, teal, #8A2BE2)" >&2
    echo "" >&2

    local choice=""
    while true; do
        read -r -p "Choose a color [1-10, c, or #hex] (default: 1): " choice </dev/tty || choice=""
        choice=$(echo "$choice" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        choice="${choice:-1}"

        if [[ "$choice" =~ ^[cC]([uU][sS][tT][oO][mM])?$ ]]; then
            read -r -p "Enter custom HTML/Hex color code (e.g. #FF5733): " custom_input </dev/tty || custom_input=""
            custom_input=$(echo "$custom_input" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            local norm
            norm=$(normalize_color "$custom_input")
            if [ -n "$norm" ]; then
                echo "$norm"
                return 0
            else
                print_error "Invalid color code '$custom_input'. Please enter a valid hex code (e.g. #3584e4 or #f00)."
                continue
            fi
        fi

        local norm
        norm=$(normalize_color "$choice")
        if [ -n "$norm" ]; then
            echo "$norm"
            return 0
        else
            print_error "Invalid selection '$choice'. Enter a number (1-10), 'c', or a valid hex code."
        fi
    done
}

generate_custom_icon() {
    local hex_color="$1"
    local initial="$2"
    local svg_out="$3"
    local png_out="$4"
    local with_badge="$5"

    python3 -c "
import sys

base_hex = sys.argv[1].strip()
initial = sys.argv[2].strip()
svg_out = sys.argv[3].strip()
with_badge = sys.argv[4].strip() == 'true'

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip('#')
    return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return '#{:02x}{:02x}{:02x}'.format(
        max(0, min(255, int(rgb[0]))),
        max(0, min(255, int(rgb[1]))),
        max(0, min(255, int(rgb[2])))
    )

r, g, b = hex_to_rgb(base_hex)
dark = rgb_to_hex((r * 0.62, g * 0.62, b * 0.62))
shadow = rgb_to_hex((r * 0.40, g * 0.40, b * 0.40))
light = rgb_to_hex((min(255, r * 1.25), min(255, g * 1.25), min(255, b * 1.25)))

badge_xml = ''
if with_badge and initial:
    badge_xml = f'''
  <g filter=\"url(#badgeShadow)\">
    <circle cx=\"100\" cy=\"100\" r=\"19\" fill=\"#ffffff\" stroke=\"{base_hex}\" stroke-width=\"2.5\"/>
    <text x=\"100\" y=\"106.5\" font-family=\"system-ui, -apple-system, sans-serif\" font-size=\"18\" font-weight=\"900\" fill=\"{base_hex}\" text-anchor=\"middle\">{initial}</text>
  </g>'''

svg = f'''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<svg viewBox=\"0 0 128 128\" width=\"128\" height=\"128\" version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" data-color=\"{base_hex}\">
  <defs>
    <linearGradient id=\"shadowGradient\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">
      <stop offset=\"0%\" stop-color=\"{shadow}\"/>
      <stop offset=\"100%\" stop-color=\"{dark}\"/>
    </linearGradient>
    <linearGradient id=\"mainGradient\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">
      <stop offset=\"0%\" stop-color=\"{light}\"/>
      <stop offset=\"100%\" stop-color=\"{base_hex}\"/>
    </linearGradient>
    <filter id=\"badgeShadow\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\">
      <feDropShadow dx=\"0\" dy=\"2\" stdDeviation=\"2\" flood-color=\"#000000\" flood-opacity=\"0.35\"/>
    </filter>
  </defs>
  <!-- Base Shadow Rect -->
  <rect x=\"12\" y=\"32\" width=\"104\" height=\"84\" rx=\"10\" ry=\"10\" fill=\"url(#shadowGradient)\"/>
  <!-- Main Rect -->
  <rect x=\"12\" y=\"12\" width=\"104\" height=\"100\" rx=\"10\" ry=\"10\" fill=\"url(#mainGradient)\"/>
  <rect x=\"12\" y=\"12\" width=\"104\" height=\"100\" rx=\"10\" ry=\"10\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"1\" stroke-opacity=\"0.25\"/>
  <!-- Helium Logo Star -->
  <path fill=\"#ffffff\" d=\"m 63.757164,28.410156 a 2.150391,2.150391 0 0 0 -2.003907,2.144532 V 56.755859 L 37.409507,32.339844 c -0.820312,-0.820313 -2.148437,-0.820313 -2.96875,0 a 2.109375,2.109375 0 0 0 0,2.980468 L 58.84896,59.800781 H 32.800132 a 2.1503906,2.1503906 0 1 0 0,4.300781 h 25.957032 l -24.3125,24.386719 a 2.109375,2.109375 0 0 0 0,2.980469 2.0976563,2.0976563 0 0 0 2.96875,0 L 61.753257,67.056641 v 26.091797 a 2.150391,2.150391 0 1 0 4.300781,0 V 67.025391 l 24.371094,24.443359 0.0039,0.0039 a 2.0976563,2.0976563 0 0 0 2.964844,-0.0039 2.109375,2.109375 0 0 0 0,-2.980469 L 69.077476,64.101562 h 26.125 a 2.1484375,2.1484375 0 0 0 2.148438,-2.148437 l -0.0039,-0.0039 A 2.1484375,2.1484375 0 0 0 95.194664,59.800781 H 68.989585 L 93.397788,35.320312 a 2.109375,2.109375 0 0 0 0,-2.980468 h -0.0078 c -0.820312,-0.820313 -2.148437,-0.820313 -2.96875,0 L 66.054038,56.78125 v -26.222656 -0.0039 a 2.150391,2.150391 0 0 0 -2.296874,-2.144532 z\" />{badge_xml}
</svg>'''

with open(svg_out, 'w', encoding='utf-8') as f:
    f.write(svg)
" "$hex_color" "$initial" "$svg_out" "$with_badge"

    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 128 -h 128 "$svg_out" -o "$png_out" 2>/dev/null || true
    fi
}

get_profiles() {
    local config_dir="$1"
    local local_state="${config_dir}/Local State"

    if [ -f "$local_state" ] && jq -e '.profile.info_cache' "$local_state" &>/dev/null; then
        jq -r '.profile.info_cache | to_entries[] | "\(.key)\t\(.value.name // .key)"' "$local_state"
    else
        if [ -d "${config_dir}/Default" ]; then
            echo -e "Default\tDefault"
        fi
        for p in "${config_dir}"/Profile*; do
            if [ -d "$p" ]; then
                local b
                b=$(basename "$p")
                echo -e "${b}\t${b}"
            fi
        done
    fi
}

resolve_profile() {
    local query="$1"
    local config_dir="$2"

    local found_dir=""
    local found_name=""

    while IFS=$'\t' read -r pdir pname; do
        if [ -z "$pdir" ]; then
            continue
        fi
        if [ "$pdir" = "$query" ] || [ "$pname" = "$query" ] || \
           [ "$(echo "$pdir" | tr '[:upper:]' '[:lower:]')" = "$(echo "$query" | tr '[:upper:]' '[:lower:]')" ] || \
           [ "$(echo "$pname" | tr '[:upper:]' '[:lower:]')" = "$(echo "$query" | tr '[:upper:]' '[:lower:]')" ]; then
            found_dir="$pdir"
            found_name="$pname"
            break
        fi
    done < <(get_profiles "$config_dir")

    if [ -n "$found_dir" ]; then
        echo -e "${found_dir}\t${found_name}"
    else
        echo -e "${query}\t${query}"
    fi
}

format_title() {
    local template="$1"
    local pname="$2"
    local pdir="$3"
    echo "$template" | sed "s/{name}/$pname/g; s/{profile}/$pdir/g"
}

is_pinned_to_favorites() {
    local desktop_name="$1"
    if ! command -v gsettings &>/dev/null; then
        echo "false"
        return 0
    fi

    python3 -c "
import ast, subprocess, sys
try:
    cur = subprocess.check_output(['gsettings', 'get', 'org.gnome.shell', 'favorite-apps'], text=True).strip()
    apps = ast.literal_eval(cur)
    print('true' if sys.argv[1] in apps else 'false')
except Exception:
    print('false')
" "$desktop_name" 2>/dev/null || echo "false"
}

pin_to_favorites() {
    local desktop_name="$1"
    if ! command -v gsettings &>/dev/null; then
        print_warn "gsettings not found; skipping GNOME favorites pinning."
        return 0
    fi

    python3 -c "
import ast, subprocess, sys
try:
    cur = subprocess.check_output(['gsettings', 'get', 'org.gnome.shell', 'favorite-apps'], text=True).strip()
    apps = ast.literal_eval(cur)
    target = sys.argv[1]
    if target not in apps:
        apps.append(target)
        subprocess.check_call(['gsettings', 'set', 'org.gnome.shell', 'favorite-apps', str(apps)])
        print('PINNED')
    else:
        print('ALREADY_PINNED')
except Exception as e:
    sys.exit(1)
" "$desktop_name" 2>/dev/null && print_info "Pinned '$desktop_name' to GNOME Favorites." || print_warn "Could not pin to GNOME Favorites."
}

unpin_from_favorites() {
    local desktop_name="$1"
    if ! command -v gsettings &>/dev/null; then
        return 0
    fi

    python3 -c "
import ast, subprocess, sys
try:
    cur = subprocess.check_output(['gsettings', 'get', 'org.gnome.shell', 'favorite-apps'], text=True).strip()
    apps = ast.literal_eval(cur)
    target = sys.argv[1]
    if target in apps:
        apps = [a for a in apps if a != target]
        subprocess.check_call(['gsettings', 'set', 'org.gnome.shell', 'favorite-apps', str(apps)])
        print('UNPINNED')
except Exception:
    pass
" "$desktop_name" 2>/dev/null || true
}

# Thoroughly refresh desktop launcher and icon caches across FreeDesktop and GNOME.
refresh_caches() {
    if [ "$DRY_RUN" = "true" ]; then
        print_info "Dry-run: Would refresh desktop shortcut and icon caches."
        return 0
    fi

    print_step "Updating desktop shortcut and icon caches..."

    # 1. Update FreeDesktop application database
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$APPS_DIR" 2>/dev/null || true
    fi

    # 2. Force update XDG desktop menu
    if command -v xdg-desktop-menu &>/dev/null; then
        xdg-desktop-menu forceupdate 2>/dev/null || true
    fi

    # 3. Update GTK3 and GTK4 icon caches
    local hicolor_dir="${XDG_DATA_HOME}/icons/hicolor"
    if [ -d "$hicolor_dir" ]; then
        if command -v gtk-update-icon-cache &>/dev/null; then
            gtk-update-icon-cache -f -t -q "$hicolor_dir" 2>/dev/null || true
        fi
        if command -v gtk4-update-icon-cache &>/dev/null; then
            gtk4-update-icon-cache -f -t -q "$hicolor_dir" 2>/dev/null || true
        fi
        if command -v xdg-icon-resource &>/dev/null; then
            xdg-icon-resource forceupdate 2>/dev/null || true
        fi
    fi

    # 4. Touch directories to signal file system monitors (inotify / GNOME Shell)
    touch "$APPS_DIR" 2>/dev/null || true
    touch "${XDG_DATA_HOME}/icons/hicolor" 2>/dev/null || true

    print_success "Desktop shortcut and icon caches updated successfully."
}

cmd_list() {
    local config_dir="$1"
    print_step "Helium Configuration Directory: $config_dir"

    if [ ! -d "$config_dir" ]; then
        print_warn "Directory does not exist: $config_dir"
        exit 0
    fi

    print_step "Detected Helium Profiles & Shortcut Status:"
    printf "  %-11s %-13s %-24s %-10s %-16s %-8s\n" "DIRECTORY" "DISPLAY NAME" "SHORTCUT TITLE" "STATUS" "ICON COLOR" "FAVORITE"
    printf "  %-11s %-13s %-24s %-10s %-16s %-8s\n" "---------" "------------" "--------------" "------" "----------" "--------"

    local count=0
    while IFS=$'\t' read -r pdir pname; do
        if [ -z "$pdir" ]; then
            continue
        fi
        count=$((count + 1))
        local slug
        slug=$(slugify "$pdir")
        local desktop_file="helium-profile-${slug}.desktop"
        local full_path="${APPS_DIR}/${desktop_file}"
        local icon_svg="${ICONS_SCALABLE_DIR}/helium-profile-${slug}.svg"

        local status="Not Found"
        local display_title
        display_title=$(format_title "$TITLE_FORMAT" "$pname" "$pdir")

        if [ -f "$full_path" ]; then
            status="Installed"
            # Read actual Name= from desktop file
            local actual_name
            actual_name=$(grep -m1 '^Name=' "$full_path" 2>/dev/null | cut -d'=' -f2- || true)
            if [ -n "$actual_name" ]; then
                display_title="$actual_name"
            fi
        fi

        local color_hex=""
        if [ -f "$icon_svg" ]; then
            color_hex=$(grep -o 'data-color="[^"]*"' "$icon_svg" 2>/dev/null | cut -d'"' -f2 || true)
        fi

        local fav="No"
        if [ "$(is_pinned_to_favorites "$desktop_file")" = "true" ]; then
            fav="Yes"
        fi

        if [ -n "$color_hex" ]; then
            local swatch
            swatch=$(print_color_swatch "$color_hex")
            printf "  %-11s %-13s %-24s %-10s %b %-11s %-8s\n" "$pdir" "$pname" "$display_title" "$status" "$swatch" "$color_hex" "$fav"
        else
            printf "  %-11s %-13s %-24s %-10s     %-11s %-8s\n" "$pdir" "$pname" "$display_title" "$status" "Default" "$fav"
        fi
    done < <(get_profiles "$config_dir")

    if [ "$count" -eq 0 ]; then
        print_warn "No profiles discovered in $config_dir."
    fi
    echo ""
}

create_single_shortcut() {
    local pdir="$1"
    local pname="$2"
    local config_dir="$3"
    local selected_color="$4"
    local raw_name="$5"

    # Strictly strip newlines, carriage returns, and extra whitespace from title
    local final_name
    final_name=$(echo "$raw_name" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    local slug
    slug=$(slugify "$pdir")
    local desktop_name="helium-profile-${slug}.desktop"
    local desktop_path="${APPS_DIR}/${desktop_name}"

    local icon_entry="helium-browser"

    if [ -n "$CUSTOM_ICON" ]; then
        icon_entry="$CUSTOM_ICON"
    elif [ "$NO_COLOR" = "true" ]; then
        icon_entry="helium-browser"
    else
        local initial
        initial=$(echo "$pname" | tr -d ' ' | cut -c1 | tr '[:lower:]' '[:upper:]')
        [ -z "$initial" ] && initial="H"

        local svg_path="${ICONS_SCALABLE_DIR}/helium-profile-${slug}.svg"
        local png_path="${ICONS_128_DIR}/helium-profile-${slug}.png"

        if [ "$DRY_RUN" = "true" ]; then
            print_info "Dry-run: Would generate icon at: $svg_path with color: $selected_color"
        else
            mkdir -p "$ICONS_SCALABLE_DIR" "$ICONS_128_DIR"
            generate_custom_icon "$selected_color" "$initial" "$svg_path" "$png_path" "$WITH_BADGE"
            print_success "Generated custom profile icon: $svg_path ($(print_color_swatch "$selected_color") $selected_color)"
        fi
        icon_entry="$svg_path"
    fi

    local desktop_content
    desktop_content=$(cat << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${final_name}
GenericName=Web Browser
Comment=Access the Internet using Helium Browser profile: ${pname}
Exec=${HELIUM_BIN} --profile-directory="${pdir}" %U
Icon=${icon_entry}
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=${HELIUM_BIN} --profile-directory="${pdir}"

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=${HELIUM_BIN} --profile-directory="${pdir}" --incognito
EOF
)

    if [ "$DRY_RUN" = "true" ]; then
        print_step "Dry-run: Would create shortcut '${final_name}' at: $desktop_path"
        echo "$desktop_content"
        echo ""
        return 0
    fi

    mkdir -p "$APPS_DIR"
    echo "$desktop_content" > "$desktop_path"
    chmod +x "$desktop_path"
    print_success "Created GNOME shortcut '${final_name}': $desktop_path"

    if [ "$ADD_DESKTOP" = "true" ] && [ -d "$DESKTOP_DIR" ]; then
        local user_desktop="${DESKTOP_DIR}/${desktop_name}"
        cp "$desktop_path" "$user_desktop"
        chmod +x "$user_desktop"
        print_success "Copied shortcut to Desktop: $user_desktop"
    fi

    if [ "$PIN_FAVORITE" = "true" ]; then
        pin_to_favorites "$desktop_name"
    fi
}

cmd_create() {
    local target_profile="$1"
    local config_dir="$2"

    if [ "$PROCESS_ALL" = "true" ]; then
        print_step "Creating shortcuts for all detected profiles in $config_dir..."
        local count=0
        local palette_len=${#SUGGESTED_COLORS[@]}

        while IFS=$'\t' read -r pdir pname; do
            if [ -n "$pdir" ]; then
                local chosen_color="$CHOSEN_COLOR"
                if [ -z "$chosen_color" ] && [ "$NO_COLOR" != "true" ] && [ -z "$CUSTOM_ICON" ]; then
                    local entry="${SUGGESTED_COLORS[$((count % palette_len))]}"
                    chosen_color="${entry##*:}"
                fi

                local title
                title=$(format_title "$TITLE_FORMAT" "$pname" "$pdir")

                create_single_shortcut "$pdir" "$pname" "$config_dir" "$chosen_color" "$title"
                count=$((count + 1))
            fi
        done < <(get_profiles "$config_dir")

        if [ "$count" -eq 0 ]; then
            print_warn "No profiles found to create shortcuts for."
        else
            refresh_caches
            print_success "Created shortcuts for $count profile(s)."
        fi
    else
        if [ -z "$target_profile" ]; then
            print_error "Profile name or directory is required (or use --all)."
            usage
            exit 1
        fi

        IFS=$'\t' read -r resolved_dir resolved_name < <(resolve_profile "$target_profile" "$config_dir")
        print_info "Resolved target: Directory='$resolved_dir', Display Name='$resolved_name'"

        # 1. Resolve Shortcut Title
        local final_title=""
        if [ -n "$CUSTOM_TITLE" ]; then
            final_title="$CUSTOM_TITLE"
        else
            local default_title
            default_title=$(format_title "$TITLE_FORMAT" "$resolved_name" "$resolved_dir")
            if [ -t 0 ] && [ "$NON_INTERACTIVE" != "true" ]; then
                final_title=$(prompt_title_selection "$default_title")
            else
                final_title="$default_title"
            fi
        fi

        # 2. Resolve Shortcut Color
        local chosen_color="$CHOSEN_COLOR"
        if [ -z "$chosen_color" ] && [ "$NO_COLOR" != "true" ] && [ -z "$CUSTOM_ICON" ]; then
            if [ -t 0 ] && [ "$NON_INTERACTIVE" != "true" ]; then
                chosen_color=$(prompt_color_selection "$resolved_name")
            else
                chosen_color="#3584e4"
            fi
        fi

        create_single_shortcut "$resolved_dir" "$resolved_name" "$config_dir" "$chosen_color" "$final_title"
        refresh_caches
    fi
}

remove_single_shortcut() {
    local pdir="$1"
    local pname="$2"

    local slug
    slug=$(slugify "$pdir")
    local desktop_name="helium-profile-${slug}.desktop"
    local desktop_path="${APPS_DIR}/${desktop_name}"
    local user_desktop="${DESKTOP_DIR}/${desktop_name}"
    local svg_icon="${ICONS_SCALABLE_DIR}/helium-profile-${slug}.svg"
    local png_icon="${ICONS_128_DIR}/helium-profile-${slug}.png"

    if [ "$DRY_RUN" = "true" ]; then
        print_step "Dry-run: Would remove shortcuts and icons for '$pname' ($pdir):"
        [ -f "$desktop_path" ] && echo "  - Desktop entry : $desktop_path"
        [ -f "$user_desktop" ] && echo "  - Desktop copy  : $user_desktop"
        [ -f "$svg_icon" ] && echo "  - Scalable icon : $svg_icon"
        [ -f "$png_icon" ] && echo "  - Raster icon   : $png_icon"
        return 0
    fi

    local removed=0
    if [ -f "$desktop_path" ]; then
        rm -f "$desktop_path"
        print_success "Removed shortcut: $desktop_path"
        removed=1
    fi

    if [ -f "$user_desktop" ]; then
        rm -f "$user_desktop"
        print_success "Removed Desktop copy: $user_desktop"
        removed=1
    fi

    if [ -f "$svg_icon" ]; then
        rm -f "$svg_icon"
        print_info "Removed custom SVG icon: $svg_icon"
    fi

    if [ -f "$png_icon" ]; then
        rm -f "$png_icon"
        print_info "Removed custom PNG icon: $png_icon"
    fi

    unpin_from_favorites "$desktop_name"

    if [ "$removed" -eq 0 ]; then
        print_warn "No installed shortcut found for profile '$pname' ($desktop_name)."
    fi
}

cmd_remove() {
    local target_profile="$1"
    local config_dir="$2"

    if [ "$PROCESS_ALL" = "true" ]; then
        print_step "Removing shortcuts and icons for all detected profiles..."
        while IFS=$'\t' read -r pdir pname; do
            if [ -n "$pdir" ]; then
                remove_single_shortcut "$pdir" "$pname"
            fi
        done < <(get_profiles "$config_dir")
        refresh_caches
        print_success "Completed removing profile shortcuts and icons."
    else
        if [ -z "$target_profile" ]; then
            print_error "Profile name or directory is required (or use --all)."
            usage
            exit 1
        fi

        IFS=$'\t' read -r resolved_dir resolved_name < <(resolve_profile "$target_profile" "$config_dir")
        remove_single_shortcut "$resolved_dir" "$resolved_name"
        refresh_caches
    fi
}

# Main entry point
check_dependencies

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

COMMAND=""
TARGET_PROFILE=""

# Check if first argument is a command
case "$1" in
    list|-l)
        COMMAND="list"
        shift
        ;;
    create|add|-c)
        COMMAND="create"
        shift
        ;;
    remove|rm|delete|-r)
        COMMAND="remove"
        shift
        ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        print_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--all)
            PROCESS_ALL="true"
            shift
            ;;
        -t|--title|-n|--name)
            CUSTOM_TITLE=$(echo "$2" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            shift 2
            ;;
        --title-format|--format)
            TITLE_FORMAT="$2"
            shift 2
            ;;
        -C|--color)
            raw_c="$2"
            norm_c=$(normalize_color "$raw_c")
            if [ -z "$norm_c" ]; then
                print_error "Invalid color argument '$raw_c'. Must be a hex code (e.g. #3584e4), color name (e.g. teal), or number (1-10)."
                exit 1
            fi
            CHOSEN_COLOR="$norm_c"
            shift 2
            ;;
        --no-badge)
            WITH_BADGE="false"
            shift
            ;;
        --default-icon|--no-color)
            NO_COLOR="true"
            shift
            ;;
        -i|--icon)
            CUSTOM_ICON="$2"
            shift 2
            ;;
        --pin|--favorite)
            PIN_FAVORITE="true"
            shift
            ;;
        --desktop)
            ADD_DESKTOP="true"
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --binary)
            HELIUM_BIN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$TARGET_PROFILE" ]; then
                TARGET_PROFILE="$1"
                shift
            else
                print_error "Unexpected argument: $1"
                usage
                exit 1
            fi
            ;;
    esac
done

if [ -z "$CONFIG_DIR" ]; then
    CONFIG_DIR=$(detect_helium_config_dir)
fi

case "$COMMAND" in
    list)
        cmd_list "$CONFIG_DIR"
        ;;
    create)
        cmd_create "$TARGET_PROFILE" "$CONFIG_DIR"
        ;;
    remove)
        cmd_remove "$TARGET_PROFILE" "$CONFIG_DIR"
        ;;
esac

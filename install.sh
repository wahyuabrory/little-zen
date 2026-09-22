#!/bin/sh
set -eu

profile_path=
zen_path=

usage() {
  echo "Usage: $0 [--profile PATH] [--zen PATH]" >&2
  exit 2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) [ "$#" -ge 2 ] || usage; profile_path=$2; shift 2 ;;
    --zen) [ "$#" -ge 2 ] || usage; zen_path=$2; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
raw_base=https://raw.githubusercontent.com/wahyuabrory/little-zen/main
temp_payload=

if [ ! -f "$script_dir/littleZen.uc.js" ] || [ ! -f "$script_dir/vendor/fx-autoconfig/program/config.js" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required for remote installation."
  temp_payload=$(mktemp -d "${TMPDIR:-/tmp}/little-zen.XXXXXX") || die "Could not create a temporary directory."
  trap 'rm -rf "$temp_payload"' EXIT HUP INT TERM
  for file in \
    littleZen.uc.js \
    little-zen.css \
    vendor/fx-autoconfig/program/config.js \
    vendor/fx-autoconfig/program/defaults/pref/config-prefs.js \
    vendor/fx-autoconfig/profile/chrome/utils/boot.sys.mjs \
    vendor/fx-autoconfig/profile/chrome/utils/chrome.manifest \
    vendor/fx-autoconfig/profile/chrome/utils/fs.sys.mjs \
    vendor/fx-autoconfig/profile/chrome/utils/module_loader.mjs \
    vendor/fx-autoconfig/profile/chrome/utils/uc_api.sys.mjs \
    vendor/fx-autoconfig/profile/chrome/utils/utils.sys.mjs
  do
    mkdir -p "$temp_payload/$(dirname -- "$file")"
    curl -fsSL "$raw_base/$file" -o "$temp_payload/$file" || die "Could not download $raw_base/$file"
  done
  script_dir=$temp_payload
fi

vendor=$script_dir/vendor/fx-autoconfig

for file in littleZen.uc.js little-zen.css vendor/fx-autoconfig/program/config.js vendor/fx-autoconfig/program/defaults/pref/config-prefs.js; do
  [ -f "$script_dir/$file" ] || die "Installer payload is missing: $file"
done

if pgrep -x zen >/dev/null 2>&1 || pgrep -x "Zen Browser" >/dev/null 2>&1; then
  die "Zen is running. Close all Zen windows and run the installer again."
fi

select_profile() {
  if [ -n "$profile_path" ]; then
    [ -d "$profile_path" ] || die "Profile directory not found: $profile_path"
    (CDPATH= cd -- "$profile_path" && pwd)
    return
  fi

  case $(uname -s) in
    Darwin) roots="$HOME/Library/Application Support/zen" ;;
    Linux)
      xdg=${XDG_CONFIG_HOME:-$HOME/.config}
      roots="$xdg/zen
$HOME/.zen
$HOME/.var/app/app.zen_browser.zen/zen"
      ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac

  found=
  old_ifs=$IFS
  IFS='
'
  for root in $roots; do
    [ -f "$root/profiles.ini" ] || continue
    choices=$(awk -v root="$root" '
      function emit() {
        if (section ~ /^Profile/ && path != "") {
          full = relative == "0" ? path : root "/" path
          print "P\t" def "\t" full
        } else if (section ~ /^Install/ && def != "") {
          full = def ~ /^\// ? def : root "/" def
          print "I\t\t" full
        }
      }
      /^\[/ { emit(); section=$0; path=""; relative="1"; def="0"; next }
      /^Path=/ { path=substr($0,6); next }
      /^IsRelative=/ { relative=substr($0,12); next }
      /^Default=/ { def=substr($0,9); next }
      END { emit() }
    ' "$root/profiles.ini")
    [ -n "$choices" ] && found=${found}${found:+
}$choices
  done
  IFS=$old_ifs

  install_defaults=$(printf '%s\n' "$found" | awk -F '\t' '$1=="I" {print $3}' | while IFS= read -r p; do [ -d "$p" ] && printf '%s\n' "$p"; done | awk '!seen[$0]++')
  count=$(printf '%s\n' "$install_defaults" | awk 'NF {n++} END {print n+0}')
  [ "$count" -eq 1 ] && { printf '%s\n' "$install_defaults"; return; }
  defaults=$(printf '%s\n' "$found" | awk -F '\t' '$1=="P" && $2=="1" {print $3}' | while IFS= read -r p; do [ -d "$p" ] && printf '%s\n' "$p"; done | awk '!seen[$0]++')
  count=$(printf '%s\n' "$defaults" | awk 'NF {n++} END {print n+0}')
  [ "$count" -eq 1 ] && { printf '%s\n' "$defaults"; return; }
  paths=$(printf '%s\n' "$found" | awk -F '\t' '$1=="P" {print $3}' | while IFS= read -r p; do [ -d "$p" ] && printf '%s\n' "$p"; done | awk '!seen[$0]++')
  count=$(printf '%s\n' "$paths" | awk 'NF {n++} END {print n+0}')
  [ "$count" -eq 1 ] && { printf '%s\n' "$paths"; return; }
  printf 'Profiles found:\n%s\n' "$paths" >&2
  die "Could not select one Zen profile. Run again with --profile PATH."
}

select_zen_dir() {
  system=$(uname -s)
  if [ "$system" = Darwin ]; then
    for candidate in "$zen_path" "/Applications/Zen.app" "$HOME/Applications/Zen.app" "/Applications/Zen Browser.app"; do
      [ -n "$candidate" ] || continue
      case $candidate in
        */Contents/Resources) resources=$candidate; app=${candidate%/Contents/Resources} ;;
        *.app) app=$candidate; resources=$candidate/Contents/Resources ;;
        *) app=; resources=$candidate ;;
      esac
      if [ -n "$app" ] && [ -x "$app/Contents/MacOS/zen" ] && [ -d "$resources" ]; then printf '%s\n' "$resources"; return; fi
    done
    die "Zen.app was not found. Pass --zen /path/to/Zen.app."
  fi

  if [ -n "$zen_path" ]; then candidates=$zen_path; else
    command_path=$(command -v zen 2>/dev/null || command -v zen-browser 2>/dev/null || true)
    candidates="$command_path
$HOME/.tarball-installations/zen/zen
/opt/zen-browser/zen
/usr/lib/zen/zen
/usr/lib64/zen/zen"
  fi
  old_ifs=$IFS
  IFS='
'
  for candidate in $candidates; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate" ] && [ ! -d "$candidate" ]; then dirname -- "$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"; IFS=$old_ifs; return; fi
    if [ -x "$candidate/zen" ]; then (CDPATH= cd -- "$candidate" && pwd); IFS=$old_ifs; return; fi
  done
  IFS=$old_ifs
  if [ -d "$HOME/.var/app/app.zen_browser.zen" ]; then
    die "The Flatpak build is not supported because its application files are immutable. Install the Zen tarball, then run this script again."
  fi
  die "Zen installation was not found. Pass --zen with the directory that contains the zen binary."
}

profile=$(select_profile)
zen_dir=$(select_zen_dir)

same_file() {
  cmp -s "$1" "$2"
}

copy_strict() {
  src=$1
  dst=$2
  if [ -e "$dst" ]; then
    same_file "$src" "$dst" || die "A different autoconfig file already exists: $dst. It was not overwritten."
    return
  fi
  if ! mkdir -p "$(dirname -- "$dst")" 2>/dev/null || ! cp "$src" "$dst" 2>/dev/null; then
    if [ -n "$temp_payload" ]; then
      die "Cannot write to the Zen installation. Rerun: curl -fsSL '$raw_base/install.sh' | sudo sh -s -- --profile '$profile' --zen '$zen_dir'"
    fi
    die "Cannot write to the Zen installation. Rerun: sudo '$script_dir/install.sh' --profile '$profile' --zen '$zen_dir'"
  fi
}

atomic_write() {
  target=$1
  temp=$target.little-zen.tmp
  cat > "$temp"
  mv -f "$temp" "$target"
}

copy_strict "$vendor/program/config.js" "$zen_dir/config.js"
copy_strict "$vendor/program/defaults/pref/config-prefs.js" "$zen_dir/defaults/pref/config-prefs.js"

chrome=$profile/chrome
mkdir -p "$chrome/JS" "$chrome/CSS" "$chrome/utils"
cp "$script_dir/littleZen.uc.js" "$chrome/JS/littleZen.uc.js"
cp "$script_dir/little-zen.css" "$chrome/CSS/little-zen.css"
cp "$vendor/profile/chrome/utils/"* "$chrome/utils/"

user_chrome=$chrome/userChrome.css
import='@import url("CSS/little-zen.css");'
if [ ! -f "$user_chrome" ] || ! grep -Fqx "$import" "$user_chrome"; then
  { printf '%s\n' "$import"; [ ! -f "$user_chrome" ] || cat "$user_chrome"; } | atomic_write "$user_chrome"
fi

user_js=$profile/user.js
pref='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
if [ -f "$user_js" ]; then
  awk -v pref="$pref" '
    BEGIN { found=0 }
    /^[[:space:]]*user_pref\("toolkit\.legacyUserProfileCustomizations\.stylesheets",[[:space:]]*(true|false)[[:space:]]*\);[[:space:]]*$/ {
      if (!found) print pref
      found=1
      next
    }
    { print }
    END { if (!found) print pref }
  ' "$user_js" | atomic_write "$user_js"
else
  printf '%s\n' "$pref" | atomic_write "$user_js"
fi

printf 'Little Zen installed without Sine.\nProfile: %s\nZen:     %s\n' "$profile" "$zen_dir"
printf 'Start Zen. If the mod does not load, open about:support, select Clear startup cache, and restart.\n'

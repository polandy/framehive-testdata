#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Framehive contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Cleans the owner's originals as <set-dir>/clean.yaml says, verifies the result and
# packs it into <output-dir>/<set>.tar.zst. The originals are only read.
#
# Usage: ./clean.sh <set-dir> <originals-dir> <output-dir>
# Needs: exiftool, perl, GNU tar, zstd, b3sum, xxd (all in Framehive's `nix develop`).

set -euo pipefail

die() {
    echo "clean.sh: $*" >&2
    exit 1
}

[ $# -eq 3 ] || die "usage: ./clean.sh <set-dir> <originals-dir> <output-dir>"
set_dir=$1
originals=$2
output=$3
config="$set_dir/clean.yaml"
[ -f "$config" ] || die "$config is missing"
for tool in exiftool perl tar zstd b3sum xxd; do
    command -v "$tool" >/dev/null || die "$tool is missing; run inside nix develop"
done

# Reads a top-level `key: value` from clean.yaml.
top_level() {
    sed -n "s/^$1: *//p" "$config"
}

# Prints "original published kind" for each entry under `files:`.
file_entries() {
    awk '
        /^[a-z_]+:/ { in_files = ($1 == "files:"); next }
        !in_files { next }
        $1 == "-" && $2 == "original:" { original = $3; next }
        $1 == "published:" { published = $2; next }
        $1 == "kind:" { print original, published, $2 }
    ' "$config"
}

[ "$(top_level schema_version)" = 1 ] || die "$config: schema_version must be 1"
set_name=$(top_level set)
serial=$(top_level test_serial_number)
replace_names=$(top_level replace_original_names)
[[ $set_name =~ ^[a-z0-9-]+-v[0-9]+$ ]] || die "$config: invalid set name '$set_name'"
[[ $serial =~ ^[0-9]+$ ]] || die "$config: test_serial_number must be digits"
[[ ${replace_names:-false} =~ ^(true|false)$ ]] || die "$config: replace_original_names must be true or false"
[ -e "$output/$set_name" ] && die "$output/$set_name exists already"
mkdir -p "$output/$set_name"
target="$output/$set_name"

# The serial numbers of the originals, so that the check below can search for them.
mapfile -t original_serials < <(
    exiftool -q -m -a -s3 '-*SerialNumber' "$originals"/* | sort -u
)

# Overwrites, in place and with the same length, the copies of original serial numbers
# that remain in binary blocks exiftool cannot write (e.g. Fujifilm's RAF data).
overwrite_binary_serials() {
    local value padded
    for value in "${original_serials[@]}"; do
        [[ $value = "$serial" || $value =~ ^0+$ ]] && continue
        padded=$serial
        while [ ${#padded} -lt ${#value} ]; do padded+=$serial; done
        VALUE=$value REPLACEMENT=${padded:0:${#value}} \
            perl -0777 -pi -e 's/\Q$ENV{VALUE}\E/$ENV{REPLACEMENT}/g' "$1"
    done
}

while read -r original published kind; do
    [ -f "$originals/$original" ] || die "$originals/$original is missing"
    cp "$originals/$original" "$target/$published"
    chmod 644 "$target/$published"
    case $kind in
        image)
            # -wm w only overwrites tags that exist, so no serial number is added.
            exiftool -q -m -overwrite_original -wm w \
                "-SerialNumber=$serial" "-CameraSerialNumber=$serial" \
                "-InternalSerialNumber=$serial" "-XMP-aux:SerialNumber=$serial" \
                "-Canon:SerialNumber=$serial" "-LensSerialNumber=$serial" \
                '-gps:all=' '-xmp:gps*=' "$target/$published"
            overwrite_binary_serials "$target/$published"
            if [ "${replace_names:-false}" = true ]; then
                # The RAW file names that converters record start with the original base name.
                exiftool -q -m -overwrite_original -wm w \
                    "-OriginalRawFileName<\${OriginalRawFileName;s/^\\Q${original%.*}\\E/${published%.*}/}" \
                    "-XMP-crs:RawFileName<\${XMP-crs:RawFileName;s/^\\Q${original%.*}\\E/${published%.*}/}" \
                    "$target/$published"
            fi
            ;;
        video)
            # Copied unchanged; the checks below fail if it holds a serial number or GPS tag.
            ;;
        sidecar)
            sed -i "s|xmpMM:DerivedFrom=\"${original%.xmp}\"|xmpMM:DerivedFrom=\"${published%.xmp}\"|" \
                "$target/$published"
            grep -q "xmpMM:DerivedFrom=\"${published%.xmp}\"" "$target/$published" ||
                die "$published: xmpMM:DerivedFrom was not updated"
            # darktable writes GPS as one attribute per line; the check below catches any other form.
            sed -i -E '/^[[:space:]]*exif:GPS[A-Za-z]*="[^"]*"[[:space:]]*$/d' "$target/$published"
            ;;
        *) die "$config: unknown kind '$kind'" ;;
    esac
done < <(file_entries)

# Verify: no original serial number in any form, no GPS, every serial is the test value.
for file in "$target"/*; do
    hex=$(xxd -p "$file" | tr -d '\n')
    for value in "${original_serials[@]}"; do
        # An all-zero serial number identifies nothing and matches any run of zeros.
        [[ $value = "$serial" || $value =~ ^0+$ ]] && continue
        grep -qaF -- "$value" "$file" && die "$file still contains the serial number"
        if [[ $value =~ ^[0-9]+$ ]] && [ "$value" -lt 4294967296 ]; then
            big=$(printf '%08x' "$value")
            little=${big:6:2}${big:4:2}${big:2:2}${big:0:2}
            [[ $hex == *"$big"* || $hex == *"$little"* ]] &&
                die "$file still contains the serial number as a 32-bit value"
        fi
    done
    if [ "${replace_names:-false}" = true ]; then
        while read -r original _ _; do
            grep -qaF -- "${original%%.*}" "$file" && die "$file still contains the name ${original%%.*}"
        done < <(file_entries)
    fi
    [ -z "$(exiftool -q -m -a -s3 '-gps:all' '-xmp:gps*' "$file")" ] ||
        die "$file still has GPS tags"
    exiftool -q -m -a -s3 '-*SerialNumber' "$file" | grep -qv "^$serial\$" &&
        die "$file has a serial number other than $serial"
done

# A reproducible archive: sorted names, fixed times and owners.
archive="$output/$set_name.tar.zst"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --format=gnu \
    -C "$target" -cf - . | zstd -q -19 -o "$archive"

hash=$(b3sum --no-names "$archive")
size=$(stat -c %s "$archive")
echo "exiftool $(exiftool -ver), archive $archive"
echo "testdata.lock: $hash $size <path>/ https://github.com/polandy/framehive-testdata/releases/download/$set_name/$set_name.tar.zst"

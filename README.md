<!--
SPDX-FileCopyrightText: 2026 Framehive contributors
SPDX-License-Identifier: GPL-3.0-or-later
-->

# framehive-testdata

Reference photos for the tests of [Framehive](https://github.com/polandy/framehive).
The Framehive repository holds text only (its ADR 0017), so the photos live here as
release assets, one `.tar.zst` archive per reference set. Framehive pins each archive
in its `testdata.lock` by BLAKE3 hash and size, and `cargo xtask testdata fetch`
downloads and unpacks it (ADR 0027).

## Licence

The photos are **not** free content. They are the project owner's photos, and the
copyright stays with the owner. The [Framehive Test Data Licence](LICENSES/LicenseRef-Framehive-Test-Data.txt)
permits downloading, copying and redistributing them only for developing and testing
Framehive, including modified versions of it. Any other use needs written permission.

The scripts, `clean.yaml` files and this README are GPL-3.0-or-later, like Framehive.

## Sets

| Set (release tag) | Unpacked to | Files | Used by |
|---|---|---|---|
| `canon-eos-350d-v1` | `dng/canon-eos-350d/` | Lightroom DNG and camera JPEG of one shot, with darktable sidecars | Framehive CORE-004, CORE-010, PREVIEWS-001 |
| `canon-eos-7d-v1` | `canon/eos-7d/` | Lightroom DNG and camera JPEG of one shot, with darktable sidecars | Framehive CORE-003, CORE-005, CORE-010, IMPORT-021, PREVIEWS-001 |
| `canon-eos-7d-v2` | `canon/eos-7d-v2/` | CR2 and camera JPEG of one shot in Adobe RGB (`_MG_` prefix), and an `MVI_` MOV without THM | Framehive CORE-001, CORE-003, ADR 0017 |
| `fujifilm-x-t2-v1` | `fujifilm/x-t2/` | Lossless compressed RAF and camera JPEG of one shot, with darktable sidecars | Framehive CORE-001, CORE-005, CORE-010, IMPORT-021, PREVIEWS-001 |
| `fujifilm-x-t5-v1` | `fujifilm/x-t5/` | Lossless compressed RAF and camera JPEG of one shot, with darktable sidecars | Framehive CORE-001, CORE-005, CORE-010, IMPORT-021, PREVIEWS-001 |

Each set has a directory here with its `clean.yaml`, which documents every change made
to the originals.

## Rules

- **Releases are immutable.** A published asset is never replaced or deleted. A change
  is a new set version (`-v2`) and a new line in Framehive's `testdata.lock`.
- **Originals are never published**, not in a release, not in the Git history. Only the
  output of `clean.sh` is uploaded.
- **Cleaning removes:** every serial number (replaced by the documented test value
  `test_serial_number`, so that tests can read one), every GPS tag, and photos with
  recognisable people are not used at all.
- **Names are neutral.** Published names say camera and subject, never place, trip or
  date. With `replace_original_names: true`, `clean.sh` also rewrites the original
  name inside the files (`OriginalRawFileName`, `crs:RawFileName`) and refuses the
  result if any original name remains.

## Publishing a set

Inside Framehive's `nix develop` (for exiftool, perl, GNU tar, zstd, b3sum and xxd):

```sh
./clean.sh <set-dir> <originals-dir> <output-dir>
gh release create <set> <output-dir>/<set>.tar.zst --repo polandy/framehive-testdata \
  --title <set> --notes "See <set-dir>/clean.yaml."
```

`clean.sh` copies the originals, cleans the copies, refuses the result if an original
serial number (as text or as a 32-bit value) or a GPS tag remains, and packs a
reproducible archive. exiftool cannot write every place a camera stores its serial
number (Fujifilm RAF files repeat it in a binary block), so `clean.sh` also overwrites
any remaining copy of an original serial number in place, with the test value at the
same length. Sidecars lose their `exif:GPS*` properties. It prints the `testdata.lock` line to add to Framehive.

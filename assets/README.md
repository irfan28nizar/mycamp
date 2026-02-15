# Assets Structure

This folder contains all app assets used by Flutter (`pubspec.yaml`) and packaged into Android/iOS builds.

## Folder Tree

```text
assets/
  README.md
  images/
    campus/
    auth/
    ui/
      overlays/
    icons/
  maps/
    raster/
      normal/
      dark/
      low_res/
    vector_geojson/
      buildings/
      walkways/
      shortcuts/
  fonts/
```

## Folder Purpose

- `images/campus/`
  - Campus-related visuals used in general app screens.
  - Example: campus hero banners, location thumbnails.

- `images/auth/`
  - Authentication-specific images.
  - Example: login background image.

- `images/ui/overlays/`
  - UI decoration layers, badges, and overlays.
  - Keep these separate from core icons.

- `images/icons/`
  - Bitmap/icon assets used in UI where vector icons are not enough.
  - Example: custom marker icons, branded symbol assets.

- `maps/raster/normal/`
  - Default map image tiles or static map slices for offline mode.

- `maps/raster/dark/`
  - Dark-theme map image variants.

- `maps/raster/low_res/`
  - Lightweight map images for lower-end devices or fallback mode.

- `maps/vector_geojson/buildings/`
  - GeoJSON files describing building polygons/metadata.

- `maps/vector_geojson/walkways/`
  - GeoJSON files for pedestrian paths.

- `maps/vector_geojson/shortcuts/`
  - GeoJSON files for shortcut routes.

- `fonts/`
  - Custom font files (`.ttf`, `.otf`) registered in `pubspec.yaml`.

## Naming Conventions (snake_case)

Use lowercase snake_case for all file and folder names.

- Good:
  - `campus_main_gate.jpg`
  - `login_background_day.png`
  - `map_tile_12_345_678.png`
  - `buildings_block_a.geojson`

- Avoid:
  - `CampusMainGate.jpg`
  - `loginBackground.png`
  - `Map-Tile.png`

## Separation Rules

- Do not mix map images and GeoJSON in the same folder.
- Keep auth images under `images/auth/` only.
- Keep reusable UI imagery in `images/ui/` and `images/icons/`.

## Flutter Registration Notes

Register required paths in `pubspec.yaml` under `flutter/assets` and `flutter/fonts`.
Keep directory-level registration aligned with this structure to simplify scaling.

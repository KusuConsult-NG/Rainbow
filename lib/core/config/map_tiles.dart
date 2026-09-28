/// Where map tiles come from, and why not from where they used to.
///
/// ## The watermark
///
/// Every map in this app drew from
/// `https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png` — CARTO's
/// dark basemap, chosen for the tactical look. CARTO now requires an account for
/// those tiles and serves unauthenticated requests a placeholder image reading
/// **"API key required"**. So the command map in a live emergency operations
/// centre renders as a grid of watermarks: no streets, no landmarks, just the
/// markers floating on a message about billing.
///
/// It is worse than a missing basemap. A blank grey map is obviously broken; a
/// map covered in text looks like a configuration error somebody else will fix,
/// and the markers are still there, so an operator may well carry on using it
/// without realising they have lost every geographic reference.
///
/// ## Why OpenStreetMap, darkened locally
///
/// OSM's standard tiles need no key and no account. They are light, and this
/// app's whole visual language is dark, so the darkening happens on THIS side
/// with a colour filter rather than by paying a provider for a dark variant.
/// That is a deliberate trade: a filtered light basemap is not as handsome as a
/// purpose-built dark one, and it cannot stop working because of somebody's
/// pricing change.
///
/// ## What this does not solve
///
/// OSM's tile policy is aimed at modest use and asks heavy consumers to run
/// their own infrastructure or use a commercial provider. A statewide emergency
/// service in daily operation is not modest use. The honest answer for
/// production is a keyed provider or self-hosted tiles, and [urlTemplate] is
/// configurable precisely so that swapping to one is a config change and not a
/// code change: set `MAP_TILE_URL` and, if the provider needs it, put the key in
/// the URL.
///
/// Two things that follow from tiles being remote at all, and which the offline
/// work does not change: with no network there is no basemap, only markers on
/// grey; and a tile request tells the tile server roughly where the person
/// looking at the map is interested in. Neither is a reason to keep a watermark.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// The default basemap: OpenStreetMap standard, no key required.
const String defaultMapTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Attribution OSM's licence requires, and which must be shown on the map.
const String mapAttribution = '© OpenStreetMap contributors';

/// The tile URL this build should use.
///
/// `MAP_TILE_URL` in `.env` overrides it, so a keyed or self-hosted provider is
/// a configuration change. Anything that is not an https URL is refused rather
/// than passed to the tile layer, because a malformed template produces an
/// entirely blank map with nothing in the logs to say why.
String get mapTileUrl {
  if (!dotenv.isInitialized) return defaultMapTileUrl;
  final configured = dotenv.env['MAP_TILE_URL']?.trim();
  if (configured == null || configured.isEmpty) return defaultMapTileUrl;
  if (!configured.startsWith('https://') || !configured.contains('{z}')) {
    debugPrint(
      '[MAP] MAP_TILE_URL is not a usable tile template — using OpenStreetMap. '
      'It must be an https URL containing {z}, {x} and {y}.',
    );
    return defaultMapTileUrl;
  }
  return configured;
}

/// Whether the configured tiles are already dark.
///
/// A provider's own dark basemap must not be darkened again — inverting an
/// already-dark tile produces a light map, which is the same bug with the
/// opposite sign. Detected from the URL rather than configured separately,
/// because two settings that must agree are two settings that will not.
bool get mapTilesAreAlreadyDark {
  final url = mapTileUrl.toLowerCase();
  return url.contains('dark') || url.contains('night');
}

/// Turns a light basemap into a dark one, locally.
///
/// Invert, then pull the result back towards neutral so that inverted blue water
/// does not come out orange. Applied to the TILES ONLY — markers and polylines
/// are drawn above it and keep their own colours, which is the point: a filter
/// over the whole map would turn a red critical marker green.
const ColorFilter darkenTiles = ColorFilter.matrix(<double>[
  -0.9, 0, 0, 0, 240, //
  0, -0.9, 0, 0, 240, //
  0, 0, -0.9, 0, 240, //
  0, 0, 0, 1, 0, //
]);

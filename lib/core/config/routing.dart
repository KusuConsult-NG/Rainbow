/// Where road routing comes from, and why it is configurable.
///
/// `safe_zone_screen.dart` asks a routing service for ways from where somebody
/// is standing to a shelter, then picks the one that passes furthest from a
/// live threat. That request went to `router.project-osrm.org` — the OSRM
/// project's **public demonstration server** — with the URL written into the
/// screen.
///
/// That server is explicitly not for production use. It rate-limits, and it
/// answers what it refuses with a 4xx. In the field it returned **403**, and
/// the screen that tells a frightened person where to run drew nothing at all.
///
/// This is the same lesson as `map_tiles.dart` one file over, which exists
/// because CARTO's basemap started answering unauthenticated requests with a
/// tile reading "API key required". That was learned for TILES and not for
/// ROUTING, in the same feature, by the same screen. See
/// E2E_AUDIT_REPORT.md T-83.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// OSRM's public demonstration server.
///
/// Kept as the default so a developer build works with no configuration, and
/// named here rather than buried in a screen so that "we are pointed at a demo
/// server" is a fact somebody can read. A statewide service in daily operation
/// must set `ROUTING_URL` to a keyed provider or its own OSRM instance.
const String defaultRoutingBaseUrl = 'https://router.project-osrm.org';

/// Whether this build is pointed at somebody else's demonstration server.
///
/// Used to put the warning in the log once, at the point of use, rather than
/// relying on anybody reading this file.
bool get routingIsDemoServer => routingBaseUrl == defaultRoutingBaseUrl;

/// The routing service this build should use.
///
/// `ROUTING_URL` in `.env` overrides it. Anything that is not an https URL is
/// refused rather than passed to the client, because a malformed base URL
/// produces a screen with no route and nothing in the log to say why — which
/// is exactly the failure this file was written after.
String get routingBaseUrl {
  if (!dotenv.isInitialized) return defaultRoutingBaseUrl;
  final configured = dotenv.env['ROUTING_URL']?.trim();
  if (configured == null || configured.isEmpty) return defaultRoutingBaseUrl;
  if (!configured.startsWith('https://')) {
    debugPrint(
      '[ROUTING] ROUTING_URL is not an https URL — using the OSRM demo '
      'server. A routing base URL must start with https://.',
    );
    return defaultRoutingBaseUrl;
  }
  return configured.endsWith('/')
      ? configured.substring(0, configured.length - 1)
      : configured;
}

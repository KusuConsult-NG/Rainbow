import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { contentSecurityPolicy, newNonce } from './csp';

/** The one directive a blank map lives or dies by. */
function imgSrc(policy: string): string {
  return policy.split(';').map((d) => d.trim()).find((d) => d.startsWith('img-src')) || '';
}

const ORIGINAL = { ...process.env };

describe('the content security policy', () => {
  beforeEach(() => {
    delete process.env.NEXT_PUBLIC_MAP_TILE_URL;
  });

  afterEach(() => {
    process.env = { ...ORIGINAL };
  });

  it('allows the tile host the map actually requests', () => {
    // The defect: img-src listed `https://*.tile.openstreetmap.org` only, and
    // the map requests `https://tile.openstreetmap.org/{z}/{x}/{y}.png`. A CSP
    // wildcard matches a SUBDOMAIN of a host, never the host itself, so every
    // tile was refused and the command map rendered as blank grey with the
    // markers floating on it. Caught in Chromium, not by reading the header.
    const directive = imgSrc(contentSecurityPolicy(newNonce(), false));
    expect(directive).toContain('https://tile.openstreetmap.org');
  });

  it('still allows the subdomain form, which Leaflet templates often use', () => {
    const directive = imgSrc(contentSecurityPolicy(newNonce(), false));
    expect(directive).toContain('https://*.tile.openstreetmap.org');
  });

  it('allows a configured provider, so a keyed tile server is not silently blank', () => {
    process.env.NEXT_PUBLIC_MAP_TILE_URL =
      'https://tiles.plateau.example/styles/dark/{z}/{x}/{y}.png?key=abc';
    const directive = imgSrc(contentSecurityPolicy(newNonce(), false));
    expect(directive).toContain('https://tiles.plateau.example');
  });

  it('turns Leaflet’s {s} subdomain placeholder into a wildcard', () => {
    process.env.NEXT_PUBLIC_MAP_TILE_URL = 'https://{s}.tiles.example/{z}/{x}/{y}.png';
    const directive = imgSrc(contentSecurityPolicy(newNonce(), false));
    expect(directive).toContain('https://*.tiles.example');
  });

  it('refuses to widen the policy for a non-https tile URL', () => {
    process.env.NEXT_PUBLIC_MAP_TILE_URL = 'http://tiles.insecure.example/{z}/{x}/{y}.png';
    const directive = imgSrc(contentSecurityPolicy(newNonce(), false));
    expect(directive).not.toContain('tiles.insecure.example');
  });

  it('no longer carries CARTO, which nothing requests', () => {
    // It serves an "API key required" placeholder to unauthenticated callers,
    // which is what moved the map off it in the first place.
    const directive = imgSrc(contentSecurityPolicy(newNonce(), false));
    expect(directive).not.toContain('cartocdn');
  });

  it('keeps the parts of the policy that are not about maps', () => {
    const policy = contentSecurityPolicy('test-nonce', false);
    expect(policy).toContain("default-src 'self'");
    expect(policy).toContain("'nonce-test-nonce'");
    expect(policy).toContain("object-src 'none'");
    expect(policy).not.toContain('unsafe-eval');
  });
});

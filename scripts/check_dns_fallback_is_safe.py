#!/usr/bin/env python3
"""The DNS fallback must not become a way to weaken TLS.

    python3 scripts/check_dns_fallback_is_safe.py

## What this is guarding

A handset in Plateau, showing four bars of 4G, could not resolve the backend:

    SocketException: Failed host lookup: '<project>.supabase.co'
    (OS Error: No address associated with hostname, errno = 7)

That errno is an EMPTY ANSWER, not a missing name. The same URL opened in
Chrome on the same phone, because Chrome can resolve over DNS-over-HTTPS while
Flutter goes through the system `getaddrinfo()`. A Private DNS profile, a
filtering carrier resolver or a VPN all produce that split, and none of them
is something a citizen reporting a kidnapping can be asked to fix.

So the app resolves the name itself (`lib/core/net/`). That is a reasonable
thing to do and a dangerous one to do carelessly, because the obvious way to
make "connect to an IP" work is to stop checking the certificate — at which
point a DNS workaround has become a man-in-the-middle hole on an app that
carries duress PINs and the locations of people in danger.

## What this checks

  1. Every connection the app secures names the HOST it is securing. With a
     `connectionFactory` installed, `dart:io` does NOT wrap a direct socket in
     TLS — so the app does it, and `SecureSocket.secure(socket, host: name)`
     is what sends SNI and validates the certificate against the NAME while
     the socket is open to the ADDRESS. Without `host:` the certificate is
     checked against an IP and every resolved connection is unverified.
  2. No `badCertificateCallback` anywhere in `lib/` returns true. That is the
     other way to make this "work", and it turns the fallback into a hole.
  3. The fallback resolvers are addressed by LITERAL IP. A resolver named by
     hostname has to be resolved by the resolver that is broken, which is the
     one thing the fallback cannot rely on.
  4. The overrides are installed in `main()`. `dart:io` holds the client it
     uses for WebSockets in a `static final`, so an install that happens after
     the first socket leaves the realtime channel on the unmodified client for
     the rest of the session — and realtime is the connection that failed.

Comments are blanked first, so this file's own prose and the explanations in
`lib/core/net/` can quote what they are describing.
"""
from __future__ import annotations

import ipaddress
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / 'lib'
NET = LIB / 'core' / 'net'

failures: list[str] = []


def live(path: Path) -> str:
    src = path.read_text()
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'), src,
                 flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n')
    )


# 1. Every secure() names the host it is validating against.
SECURE = re.compile(r'SecureSocket\s*\.\s*secure\s*\(', re.S)

for path in sorted(LIB.rglob('*.dart')):
    code = live(path)
    for match in SECURE.finditer(code):
        depth, end = 0, len(code)
        for index in range(match.end() - 1, len(code)):
            if code[index] == '(':
                depth += 1
            elif code[index] == ')':
                depth -= 1
                if depth == 0:
                    end = index
                    break
        call = code[match.start():end]
        line = code[:match.start()].count('\n') + 1
        if not re.search(r'\bhost\s*:', call):
            failures.append(
                f'{path.relative_to(REPO)}:{line} secures a socket without '
                '`host:`. The certificate is then checked against whatever '
                'the socket connected to — an IP address, for a resolved '
                'connection — so the connection is encrypted and '
                'unauthenticated. Pass the hostname.')

    # 2. Nothing accepts a certificate it could not verify.
    for match in re.finditer(r'badCertificateCallback', code):
        line = code[:match.start()].count('\n') + 1
        window = code[match.start():match.start() + 400]
        if re.search(r'=>\s*true|return\s+true', window):
            failures.append(
                f'{path.relative_to(REPO)}:{line} installs a '
                '`badCertificateCallback` that accepts. On an app carrying '
                'duress PINs and the locations of people in danger, that is '
                'not a workaround for anything.')

# 3. The fallback resolvers need no DNS of their own.
resolver = NET / 'doh_resolver.dart'
if not resolver.is_file():
    failures.append(
        'lib/core/net/doh_resolver.dart is gone. If the DNS fallback was '
        'removed on purpose, remove this check in the same commit and say '
        'why; a handset that cannot resolve the backend is how this started.')
else:
    code = live(resolver)
    block = re.search(
        r'publicEndpoints\s*=\s*<String>\[(.*?)\]', code, re.S)
    if not block:
        failures.append(
            'lib/core/net/doh_resolver.dart no longer declares '
            '`publicEndpoints`, so this check cannot see what the fallback '
            'would talk to.')
    else:
        urls = re.findall(r"'([^']+)'", block.group(1))
        if not urls:
            failures.append('the fallback resolver list is empty.')
        for url in urls:
            host = urlparse(url).hostname or ''
            try:
                ipaddress.ip_address(host)
            except ValueError:
                failures.append(
                    f'the fallback resolver {url!r} is named by hostname. '
                    'Resolving it needs the resolver that is broken — which '
                    'is the whole reason this code exists. Address it by IP.')
            if urlparse(url).scheme != 'https':
                failures.append(
                    f'the fallback resolver {url!r} is not https. A plaintext '
                    'resolver can be answered by anyone on the path, and the '
                    'answer decides where the app connects.')

# 4. Installed before anything opens a socket.
main = live(LIB / 'main.dart')
if 'ResolvingHttpOverrides.install()' not in main:
    failures.append(
        'lib/main.dart does not call `ResolvingHttpOverrides.install()`. '
        '`dart:io` keeps the client it uses for WebSockets in a `static '
        'final`, so installing late leaves the realtime channel on the '
        'unmodified client — and realtime is the connection that failed on '
        'the handset.')
else:
    install = main.index('ResolvingHttpOverrides.install()')
    for later in ('Supabase.initialize', 'SupabaseConfig.init'):
        at = main.find(later)
        if at != -1 and at < install:
            line = main[:at].count('\n') + 1
            failures.append(
                f'lib/main.dart:{line} reaches `{later}` before '
                '`ResolvingHttpOverrides.install()`. Anything that opens a '
                'socket first gets the unmodified client.')

if failures:
    print('The DNS fallback is not safe as written:\n')
    for message in failures:
        print(f'  * {message}\n')
    sys.exit(1)

print('OK: the DNS fallback cannot weaken a connection.')
print('  * every SecureSocket.secure() names the host it validates against')
print('  * no badCertificateCallback accepts')
print('  * every fallback resolver is an https URL at a literal IP')
print('  * the overrides are installed before anything connects')

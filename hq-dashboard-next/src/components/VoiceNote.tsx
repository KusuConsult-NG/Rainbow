'use client';

/**
 * The reporter's voice, played in the page.
 *
 * ## What this replaces
 *
 * An audio recording reached this console as one of `media_urls` and was drawn
 * as a 72px thumbnail with a musical note on it, among the photographs.
 * Clicking it opened a new browser tab, where a Cloudinary `/raw/` url is as
 * likely to be DOWNLOADED as played. So the one artefact that carries what a
 * person who could not type actually said was the hardest thing on the dossier
 * to hear.
 *
 * `<audio controls>` needs no library: the browser's own player has a play
 * button, a scrubber, a volume control and a keyboard interface, all of which
 * would otherwise have to be built and none of which would be better.
 * `preload="metadata"` fetches the header and not the audio — an operator
 * opening a dossier should not pull every recording on it.
 */
export default function VoiceNote({
  url,
  seconds,
  label = 'VOICE NOTE FROM THE REPORTER',
}: {
  url: string;
  seconds?: number | null;
  label?: string;
}) {
  const stamp = typeof seconds === 'number' && seconds > 0
    ? `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
    : null;

  return (
    <div
      data-testid="voice-note"
      style={{
        marginBottom: 20,
        padding: 12,
        background: 'var(--input-bg)',
        border: '1px solid var(--primary)',
        borderRadius: 12,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span
          style={{
            fontSize: 9, fontWeight: 900, letterSpacing: 1.5,
            color: 'var(--primary)', fontFamily: 'var(--font-outfit), sans-serif',
          }}
        >
          {label}
        </span>
        {/* The duration BEFORE anything is fetched, from the column. An
            operator deciding whether to listen now should not have to wait for
            a download to find out it is eight seconds long. */}
        {stamp && (
          <span style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 700 }}>
            {stamp}
          </span>
        )}
      </div>
      {/* No caption track: that would be a transcript of a live emergency
          report, which nobody has. What the recogniser produced, when it
          produced anything, is the incident's own description above. */}
      <audio
        controls
        preload="metadata"
        src={url}
        aria-label={label}
        style={{ width: '100%' }}
      />
      <p style={{ fontSize: 11, color: 'var(--text-muted)', margin: '8px 0 0' }}>
        The reporter recorded this instead of typing.{' '}
        <a href={url} target="_blank" rel="noreferrer" style={{ color: 'var(--primary)' }}>
          Open the file
        </a>{' '}
        if it will not play here.
      </p>
    </div>
  );
}

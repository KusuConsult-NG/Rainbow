// The reporter's voice, on the screen an operator works from.
//
// An audio recording reached this console as one of `media_urls` and was drawn
// as a 72px thumbnail with a musical note on it, among the photographs.
// Clicking it opened a new browser tab, where a Cloudinary `/raw/` url is as
// likely to be downloaded as played. So the one artefact carrying what a
// person who could not type actually said was the hardest thing on the dossier
// to hear.
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import VoiceNote from './VoiceNote';

const URL = 'https://res.cloudinary.com/x/raw/upload/v1/voice.m4a';

describe('VoiceNote', () => {
  it('gives the operator a player, not a link to somewhere else', () => {
    const { container } = render(<VoiceNote url={URL} seconds={42} />);

    const audio = container.querySelector('audio');
    expect(audio).not.toBeNull();
    expect(audio).toHaveAttribute('controls');
    expect(audio?.getAttribute('src')).toBe(URL);
  });

  it('fetches the header and not the audio until asked', () => {
    // An operator opening a dossier should not pull every recording on it:
    // this console is used on a field connection as well as at a desk.
    const { container } = render(<VoiceNote url={URL} seconds={42} />);
    expect(container.querySelector('audio')).toHaveAttribute('preload', 'metadata');
  });

  it('says how long it runs before anything is fetched', () => {
    // From the column, not from the file. Deciding whether to listen now
    // should not require waiting for a download to find out it is 42 seconds.
    render(<VoiceNote url={URL} seconds={42} />);
    expect(screen.getByText('0:42')).toBeTruthy();
  });

  it('formats a long note in minutes', () => {
    render(<VoiceNote url={URL} seconds={102} />);
    expect(screen.getByText('1:42')).toBeTruthy();
  });

  it('shows no duration rather than a wrong one', () => {
    // `voice_note_seconds` is nullable: a row written before the column
    // existed, or by a path that did not measure it, has a url and no length.
    // "0:00" next to a playable recording is a lie about its content.
    const { container } = render(<VoiceNote url={URL} />);
    expect(container.textContent).not.toContain('0:00');
    expect(container.querySelector('audio')).not.toBeNull();
  });

  it('is named for what it is, for a screen reader', () => {
    render(<VoiceNote url={URL} seconds={8} />);
    expect(screen.getByLabelText(/VOICE NOTE FROM THE REPORTER/)).toBeTruthy();
  });

  it('says whose voice it is, and offers the file when it will not play', () => {
    // The fallback is the honest half: a codec this browser cannot decode is a
    // real outcome, and an operator who cannot hear a report needs the file
    // rather than a silent player.
    const { container } = render(<VoiceNote url={URL} seconds={8} />);

    expect(container.textContent).toContain('recorded this instead of typing');
    const link = screen.getByRole('link', { name: /open the file/i });
    expect(link).toHaveAttribute('href', URL);
    expect(link).toHaveAttribute('rel', 'noreferrer');
  });

  it('can be labelled for a recording that is not the reporter speaking', () => {
    render(<VoiceNote url={URL} label="RECORDING ATTACHED TO THIS INCIDENT" />);
    expect(screen.getByLabelText(/RECORDING ATTACHED/)).toBeTruthy();
  });
});

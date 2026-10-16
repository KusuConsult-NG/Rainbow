// The statewide escalation policy, on a form that can overwrite it.
//
// `SystemConfig` loaded the three timeouts with
// `.then(({ data }) => ...)` — destructuring `data` and dropping `error`. A
// refused or failed read left the seeded placeholders 2 / 5 / 10 on screen with
// nothing saying the read had not happened, and Save upserts all three rows, so
// an operator who pressed it replaced the real statewide policy with
// placeholders. The component already had an `error` state; only the SAVE path
// ever set it.
//
// Four of these fail against that version.
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeSupabaseStub, type SupabaseStub } from '@/test/supabase-stub';

let db: SupabaseStub;

vi.mock('@/lib/supabase', () => ({
  get supabase() {
    return db.client;
  },
}));

const configured = (pu: string, ward: string, lga: string) => [
  { key: 'escalation_timeout_pu', value: pu },
  { key: 'escalation_timeout_ward', value: ward },
  { key: 'escalation_timeout_lga', value: lga },
];

async function load() {
  return (await import('./SystemConfig')).default;
}

const save = () => screen.getByRole('button', { name: /save configuration/i });
const field = (label: RegExp) => screen.getByLabelText(label) as HTMLInputElement;

describe('SystemConfig', () => {
  beforeEach(() => {
    db = makeSupabaseStub();
    db.setRows('app_config', configured('3', '7', '20'));
  });

  it('shows what the database actually holds', async () => {
    const SystemConfig = await load();
    render(<SystemConfig />);

    await waitFor(() => expect(field(/polling unit/i).value).toBe('3'));
    expect(field(/ward/i).value).toBe('7');
    expect(field(/lga/i).value).toBe('20');
    expect(save()).toBeEnabled();
  });

  it('does not present the placeholders as the configuration when the read fails', async () => {
    // The seeded values happen to be 2 / 5 / 10, so this was invisible until
    // somebody changed them — and then a failed read showed the old numbers.
    db.setError('app_config', { message: 'permission denied for table app_config' });
    const SystemConfig = await load();
    render(<SystemConfig />);

    expect(await screen.findByText(/permission denied/i)).toBeInTheDocument();
    expect(screen.queryByDisplayValue('2')).not.toBeInTheDocument();
    expect(screen.queryByDisplayValue('5')).not.toBeInTheDocument();
    expect(screen.queryByDisplayValue('10')).not.toBeInTheDocument();
  });

  it('refuses to save over a policy it could not read', async () => {
    // The consequence that makes the above more than cosmetic: Save upserts
    // ALL THREE keys, so saving from an unknown baseline replaces the live
    // statewide policy with whatever is on screen.
    db.setError('app_config', { message: 'network error' });
    const SystemConfig = await load();
    render(<SystemConfig />);

    await screen.findByText(/network error/i);
    expect(save()).toBeDisabled();
    await userEvent.click(save());
    expect(db.inserts.find(i => i.table === 'app_config')).toBeUndefined();
  });

  it('says which key is missing rather than inventing a value for it', async () => {
    // A key with no row has never been configured. The migration seeds all
    // three, so a missing one means the migration has not been applied here —
    // worth saying, not worth papering over.
    db.setRows('app_config', [{ key: 'escalation_timeout_pu', value: '3' }]);
    const SystemConfig = await load();
    render(<SystemConfig />);

    expect(await screen.findByText(/not configured/i)).toBeInTheDocument();
    // Named, both of them: "something is unconfigured" is not actionable.
    expect(screen.getByText(/escalation_timeout_ward/)).toBeInTheDocument();
    expect(screen.getByText(/escalation_timeout_lga/)).toBeInTheDocument();
    // The one that IS configured shows its real value, not the placeholder.
    expect(field(/polling unit/i).value).toBe('3');
    // And saving is how you set the missing ones, so it stays available.
    expect(save()).toBeEnabled();
  });

  it('treats a non-numeric stored value as a fault, not as NaN', async () => {
    // `value` is TEXT. `Number('')` is 0 and `Number('ten')` is NaN, and
    // `String(NaN)` is what Save would have written back.
    db.setRows('app_config', configured('3', 'ten', '20'));
    const SystemConfig = await load();
    render(<SystemConfig />);

    expect(await screen.findByText(/escalation_timeout_ward/)).toBeInTheDocument();
    expect(save()).toBeDisabled();
  });

  it('writes all three keys when the baseline is known', async () => {
    const SystemConfig = await load();
    render(<SystemConfig />);
    await waitFor(() => expect(field(/polling unit/i).value).toBe('3'));

    await userEvent.clear(field(/polling unit/i));
    await userEvent.type(field(/polling unit/i), '4');
    await userEvent.click(save());

    await waitFor(() => {
      const written = db.inserts.find(i => i.table === 'app_config');
      expect(written).toBeDefined();
      expect(written!.values).toEqual([
        expect.objectContaining({ key: 'escalation_timeout_pu', value: '4' }),
        expect.objectContaining({ key: 'escalation_timeout_ward', value: '7' }),
        expect.objectContaining({ key: 'escalation_timeout_lga', value: '20' }),
      ]);
    });
  });

  it('refuses a value the escalation job would throw away', async () => {
    // `tier_timeout_minutes()` does `raw::INTEGER` and then rejects `<= 0`,
    // falling back to its seeded value — "a timeout of 0" is called out in the
    // migration as a dangerous default for an emergency queue. The form
    // accepted anything its number input produced, stored it, and read it back
    // as the policy while the job used something else.
    const SystemConfig = await load();
    render(<SystemConfig />);
    await waitFor(() => expect(field(/ward/i).value).toBe('7'));

    await userEvent.clear(field(/ward/i));
    await userEvent.type(field(/ward/i), '0');

    expect(await screen.findByText(/would discard this/i)).toBeInTheDocument();
    expect(save()).toBeDisabled();
    await userEvent.click(save());
    expect(db.inserts.find(i => i.table === 'app_config')).toBeUndefined();

    // And it recovers: a usable value clears the refusal.
    await userEvent.clear(field(/ward/i));
    await userEvent.type(field(/ward/i), '6');
    await waitFor(() => expect(save()).toBeEnabled());
  });

  it('refuses a fraction of a minute, which the job cannot cast', async () => {
    const SystemConfig = await load();
    render(<SystemConfig />);
    await waitFor(() => expect(field(/lga/i).value).toBe('20'));

    await userEvent.clear(field(/lga/i));
    await userEvent.type(field(/lga/i), '2.5');

    expect(await screen.findByText(/whole number of minutes/i)).toBeInTheDocument();
    expect(save()).toBeDisabled();
  });

  it('does not overwrite what the operator typed while the read was in flight', async () => {
    // The load merged its response over current state, so a value typed before
    // the response landed was replaced by the stored one with no warning.
    const SystemConfig = await load();
    render(<SystemConfig />);
    await waitFor(() => expect(field(/polling unit/i).value).toBe('3'));
    expect(field(/polling unit/i)).toBeEnabled();
  });
});

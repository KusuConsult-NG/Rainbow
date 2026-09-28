import { NextResponse } from 'next/server';
import {
  getSupabaseAdmin,
  requireRole,
  COMMAND_ROLES,
} from '@/lib/supabase-server';

/**
 * Provision a staff account.
 *
 * This route exists because the console used to create staff like this:
 *
 *     supabase.auth.signUp({ email, password,
 *       options: { data: { role: 'HQ_COMMAND', ... } } })
 *
 * and `handle_new_user()` copied that role straight onto the profile. It worked
 * — and it worked for everyone else too, because `options.data` is written by
 * the client with the anon key, which ships in the APK and in the browser. Any
 * stranger could sign up as a commander. The migration
 * `20260927000000_signup_cannot_choose_role.sql` closes that by making every
 * signup a CITIZEN, whatever it asks for, which is also why the console can no
 * longer provision staff from the browser and needs this route.
 *
 * The shape of the fix: the role is set by a SERVER holding the service key,
 * after checking who is asking. The browser never states a role that is
 * believed.
 */

/**
 * Roles this route will create. Anything else is refused by name rather than
 * quietly written, because a typo that reaches `profiles.role` produces an
 * account that matches no policy and no UI branch — a user who can sign in and
 * see nothing, with no error anywhere saying why.
 *
 * The four command tiers are the ones the console's own form offers; the rest
 * are roles the policies and the apps branch on elsewhere.
 */
const ASSIGNABLE = [
  'CITIZEN',
  'RESPONDER',
  'UNIT_COMMAND',
  'WARD_COMMAND',
  'LGA_COMMAND',
  'LGA_OFFICER',
  'HQ_COMMAND',
  'HQ_OFFICER',
  'POLICE_LIAISON',
  'ARMY_LIAISON',
  'NSCDC_LIAISON',
  'DSS_LIAISON',
  'ADMIN',
];

/**
 * Creating a peer or a superior is a different act from creating a subordinate.
 * An LGA commander may enrol responders for their own LGA; minting another HQ
 * commander is not theirs to do, and an account that can create HQ_COMMAND is
 * an account that can do anything.
 */
const ELEVATED = ['HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'];
const MAY_CREATE_ELEVATED = ['HQ_COMMAND', 'ADMIN'];

export async function POST(req: Request) {
  const auth = await requireRole(COMMAND_ROLES);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Malformed request body' }, { status: 400 });
  }

  const email = String(body.email ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  const fullName = String(body.fullName ?? '').trim();
  const phone = String(body.phone ?? '').trim();
  const role = String(body.role ?? '').trim().toUpperCase();
  const agency = body.agency ? String(body.agency).trim().toUpperCase() : null;

  if (!email || !password || !fullName) {
    return NextResponse.json(
      { error: 'Name, email and a password are all required.' },
      { status: 400 },
    );
  }
  if (password.length < 12) {
    return NextResponse.json(
      { error: 'Password must be at least 12 characters.' },
      { status: 400 },
    );
  }
  if (!ASSIGNABLE.includes(role)) {
    return NextResponse.json({ error: `Unknown role: ${role}` }, { status: 400 });
  }
  if (ELEVATED.includes(role) && !MAY_CREATE_ELEVATED.includes(auth.role)) {
    return NextResponse.json(
      { error: `${auth.role} may not create a ${role} account.` },
      { status: 403 },
    );
  }

  const admin = getSupabaseAdmin();

  // `email_confirm: true` because these accounts are handed to an officer in
  // person; there is no inbox to click a link in.
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, phone },
  });

  if (createErr || !created?.user) {
    return NextResponse.json(
      { error: createErr?.message ?? 'Could not create the account.' },
      { status: 400 },
    );
  }

  // The profile row already exists: handle_new_user() created it as a CITIZEN
  // on insert. The role is set here, by the service key, which the UPDATE guard
  // (`profiles_no_privilege_escalation`) exempts.
  const { error: roleErr } = await admin
    .from('profiles')
    .update({
      full_name: fullName,
      phone: phone || null,
      role,
      agency,
      geo_lga: body.geoLga ? String(body.geoLga) : null,
      geo_ward: body.geoWard ? String(body.geoWard) : null,
      geo_pu: body.geoPu ? String(body.geoPu) : null,
    })
    .eq('id', created.user.id);

  if (roleErr) {
    // An account that exists but carries no role is a CITIZEN with staff
    // credentials — worse than no account. Remove it rather than leave it.
    await admin.auth.admin.deleteUser(created.user.id).catch(() => {});
    return NextResponse.json(
      { error: `Account created but the role could not be set (${roleErr.message}). Rolled back.` },
      { status: 500 },
    );
  }

  return NextResponse.json({ id: created.user.id, email, role }, { status: 201 });
}

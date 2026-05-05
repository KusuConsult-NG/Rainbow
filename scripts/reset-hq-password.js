/**
 * reset-hq-password.js
 * Uses Firebase Auth REST API to force-set the admin password.
 * Run: node scripts/reset-hq-password.js
 * 
 * This uses the Firebase Auth REST "update" endpoint with an admin override.
 * Since we cannot use Admin SDK without service account JSON here,
 * this script guides you to set it via the Firebase Console directly.
 */

const TARGET_EMAIL = 'hq-001@operationrainbow.plateau.gov.ng';
const NEW_PASSWORD = '12345Gg!';

console.log('\n═══════════════════════════════════════════════════');
console.log('   OPERATION RAINBOW — HQ Admin Password Reset');
console.log('═══════════════════════════════════════════════════\n');
console.log('The account already exists. To set the password to');
console.log('the one you specified, follow ONE of these steps:\n');
console.log('OPTION A — Firebase Console (Recommended):');
console.log('  1. Go to: https://console.firebase.google.com/project/rainbow-97f1e/authentication/users');
console.log('  2. Find:', TARGET_EMAIL);
console.log('  3. Click the 3-dot menu → "Reset password"');
console.log('  4. Or click "Edit user" → change password to:', NEW_PASSWORD);
console.log('\nOPTION B — Firebase CLI:');
console.log('  firebase auth:import is not supported for password update.');
console.log('  Use the console link above.\n');
console.log('OPTION C — Admin SDK Script (if you have service account):');
console.log('  1. Download service account JSON from Firebase Console → Project Settings → Service Accounts');
console.log('  2. Set: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json');
console.log('  3. Run: node scripts/create-hq-admin.js\n');
console.log('═══════════════════════════════════════════════════');
console.log('Target email :', TARGET_EMAIL);
console.log('New password :', NEW_PASSWORD);
console.log('Login URL    : http://localhost:3001/login');
console.log('═══════════════════════════════════════════════════\n');

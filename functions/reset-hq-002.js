const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'rainbow-97f1e',
});

async function reset() {
  const email = 'hq-002@operationrainbow.plateau.gov.ng';
  const newPassword = 'hq-002';
  
  try {
    const user = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(user.uid, {
      password: newPassword,
    });
    console.log(`Successfully reset password for ${email} to ${newPassword}`);
  } catch (err) {
    console.error('Failed to reset password:', err.message);
  }
}

reset();

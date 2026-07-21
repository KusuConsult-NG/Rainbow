const fetch = require("node-fetch");
const API_KEY = "AIzaSyCXzOdIolNy2sHVUFF9AKpsojvxswmH6EE";

async function testAuth() {
  console.log("Testing Anonymous Auth...");
  const anonRes = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true })
  });
  const anonData = await anonRes.json();
  console.log("Anonymous Auth:", anonData);

  console.log("Testing Email/Password Auth...");
  const emailRes = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: "agent_PU-001@operationrainbow.plateau.gov.ng", password: "RB-PU-2026_sec_2026", returnSecureToken: true })
  });
  const emailData = await emailRes.json();
  console.log("Email/Password Auth:", emailData);
}

testAuth();

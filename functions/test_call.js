const fetch = require('node-fetch');

async function testCall() {
  try {
    const url = 'https://us-central1-rainbow-97f1e.cloudfunctions.net/validateAgentAccessCode';
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { accessCode: 'RB-PU-2026' } })
    });
    
    const result = await response.json();
    console.log("Response:", JSON.stringify(result, null, 2));
  } catch (e) {
    console.error("Error:", e);
  }
}

testCall();

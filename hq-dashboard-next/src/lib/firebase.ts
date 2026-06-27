import { initializeApp, getApps, getApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getDatabase } from 'firebase/database';
import { getFunctions } from 'firebase/functions';
import { initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY!,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN!,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID!,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET!,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID!,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID!,
};

const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);

// Initialize App Check for high-assurance environments
if (typeof window !== 'undefined') {
  if (process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY) {
    initializeAppCheck(app, {
      provider: new ReCaptchaV3Provider(process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY),
      isTokenAutoRefreshEnabled: true
    });
  }
}

export { app };
export const auth = getAuth(app);
export const db = getFirestore(app);
export const rtdb = getDatabase(app);
export const functions = getFunctions(app);

// Initialize Firebase AI Logic (Gemini API Provider)
let aiInstance: any = null;
if (typeof window !== 'undefined') {
  try {
    const { getAI, GoogleAIBackend } = require('firebase/ai');
    aiInstance = getAI(app, { backend: new GoogleAIBackend() });
  } catch (error) {
    console.error('Failed to initialize Firebase AI Logic SDK:', error);
  }
}

export const ai = aiInstance;

export const getGeminiModel = (options?: { responseMimeType?: string }) => {
  if (!ai) return null;
  const { getGenerativeModel } = require('firebase/ai');
  const generationConfig: any = {
    temperature: 0.7,
  };
  if (options?.responseMimeType) {
    generationConfig.responseMimeType = options.responseMimeType;
  }
  return getGenerativeModel(ai, {
    model: "gemini-flash-latest",
    generationConfig
  });
};


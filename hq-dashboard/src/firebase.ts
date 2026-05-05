/// <reference types="vite/client" />
import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";

// Your web app's Firebase configuration
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || "***REMOVED-SECRET***",
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || "rainbow-97f1e.firebaseapp.com",
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || "rainbow-97f1e",
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || "rainbow-97f1e.firebasestorage.app",
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || "787216891713",
  appId: import.meta.env.VITE_FIREBASE_APP_ID || "1:787216891713:web:507b7c1381e2a794a82bc0"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const auth = getAuth(app);

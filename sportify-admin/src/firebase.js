import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: "AIzaSyDqPAxBr5j21jAx4pzchYUzOPBcuz5Dg38",
  authDomain: "sportify-ee13f.firebaseapp.com",
  projectId: "sportify-ee13f",
  storageBucket: "sportify-ee13f.firebasestorage.app",
  messagingSenderId: "1095521798445",
  appId: "1:1095521798445:web:4a860102ba0c4251dcaba4",
  measurementId: "G-MDJ8P06KG8"
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export default app;
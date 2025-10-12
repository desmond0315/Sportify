import { initializeApp } from 'firebase/app';

const firebaseConfig = {
  apiKey: "AIzaSyDJjxjf2lJAj42cbVGzDRBcu2Z0g8",
  authDomain: "sportify-ee13f.firebaseapp.com", 
  projectId: "sportify-ee13f",
  storageBucket: "sportify-ee13f.appspot.com",
  messagingSenderId: "1095521798445",
  appId: "1:1095521798445:web:4a860102ba0c4251dcaba4"
};

try {
  const app = initializeApp(firebaseConfig);
  console.log('Firebase initialized successfully:', app);
} catch (error) {
  console.error('Firebase initialization error:', error);
}
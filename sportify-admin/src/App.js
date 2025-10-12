import React, { useState, useEffect } from 'react';
import { onAuthStateChanged } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import AdminLogin from './components/AdminLogin';
import AdminDashboard from './components/AdminDashboard';
import './App.css';

function App() {
  const [user, setUser] = useState(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      if (currentUser) {
        try {
          // Check if user is admin
          const adminDoc = await getDoc(doc(db, 'admin', currentUser.uid));
          
          if (adminDoc.exists()) {
            const adminData = adminDoc.data();
            if (adminData.isActive && adminData.role === 'admin') {
              setIsAdmin(true);
              setUser({
                uid: currentUser.uid,
                email: currentUser.email,
                ...adminData
              });
            } else {
              setIsAdmin(false);
              setUser(null);
            }
          } else {
            setIsAdmin(false);
            setUser(null);
          }
        } catch (error) {
          console.error('Error checking admin status:', error);
          setIsAdmin(false);
          setUser(null);
        }
      } else {
        setIsAdmin(false);
        setUser(null);
      }
      setLoading(false);
    });

    return unsubscribe;
  }, []);

  const handleLoginSuccess = (adminUser) => {
    setUser(adminUser);
    setIsAdmin(true);
  };

  if (loading) {
    return (
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        height: '100vh',
        backgroundColor: '#f7fafc'
      }}>
        <div>Loading...</div>
      </div>
    );
  }

  return (
    <div className="App">
      {isAdmin ? (
        <AdminDashboard user={user} />
      ) : (
        <AdminLogin onLoginSuccess={handleLoginSuccess} />
      )}
    </div>
  );
}

export default App;
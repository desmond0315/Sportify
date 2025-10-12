import React, { useState, useEffect } from 'react';
import { signOut } from 'firebase/auth';
import { collection, query, where, onSnapshot, getDocs } from 'firebase/firestore';
import { auth, db } from '../firebase';
import CoachApprovalPage from './CoachApprovalPage';
import VenueApprovalPage from './VenueApprovalPage';
import UserManagementPage from './UserManagementPage';
import SessionVerificationPage from './SessionVerificationPage';
import AdminPaymentManagement from './AdminPaymentManagement';

const AdminDashboard = ({ user }) => {
  const [currentPage, setCurrentPage] = useState('dashboard');
  const [pendingCoachCount, setPendingCoachCount] = useState(0);
  const [pendingVenueCount, setPendingVenueCount] = useState(0);
  const [totalUserCount, setTotalUserCount] = useState(0);
  const [pendingVerificationCount, setPendingVerificationCount] = useState(0);

  useEffect(() => {
    const coachQuery = query(collection(db, 'coach_applications'), where('status', '==', 'pending'));
    const unsubscribeCoaches = onSnapshot(coachQuery, (snapshot) => {
      setPendingCoachCount(snapshot.size);
    });

    const venueQuery = query(collection(db, 'venue_applications'), where('status', '==', 'pending'));
    const unsubscribeVenues = onSnapshot(venueQuery, (snapshot) => {
      setPendingVenueCount(snapshot.size);
    });

    const fetchTotalUsers = async () => {
      try {
        const usersSnapshot = await getDocs(collection(db, 'users'));
        const coachesSnapshot = await getDocs(collection(db, 'coaches'));
        const venueOwnersSnapshot = await getDocs(collection(db, 'venue_owners'));
        
        const total = usersSnapshot.size + coachesSnapshot.size + venueOwnersSnapshot.size;
        setTotalUserCount(total);
      } catch (error) {
        console.error('Error fetching total users:', error);
      }
    };

    const verificationQuery = query(
      collection(db, 'coach_appointments'), 
      where('status', '==', 'awaiting_verification')
    );
    const unsubscribeVerifications = onSnapshot(verificationQuery, (snapshot) => {
      setPendingVerificationCount(snapshot.size);
    });

    fetchTotalUsers();

    return () => {
      unsubscribeCoaches();
      unsubscribeVenues();
      unsubscribeVerifications();  
    };
    
  }, []);

  const handleLogout = async () => {
    try {
      await signOut(auth);
      localStorage.removeItem('adminUser');
    } catch (error) {
      console.error('Logout error:', error);
    }
  };

  const renderDashboard = () => (
    <>
      {/* Welcome Banner */}
      <div style={{
        background: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)',
        borderRadius: '16px',
        padding: '32px',
        marginBottom: '32px',
        color: 'white',
        boxShadow: '0 10px 40px rgba(59, 130, 246, 0.3)',
        position: 'relative',
        overflow: 'hidden'
      }}>
        <div style={{
          position: 'absolute',
          top: '-50px',
          right: '-50px',
          width: '200px',
          height: '200px',
          background: 'rgba(255,255,255,0.1)',
          borderRadius: '50%'
        }} />
        <div style={{
          position: 'absolute',
          bottom: '-30px',
          left: '-30px',
          width: '150px',
          height: '150px',
          background: 'rgba(255,255,255,0.05)',
          borderRadius: '50%'
        }} />
        
        <div style={{ position: 'relative', zIndex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="white">
              <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z"/>
            </svg>
            <h1 style={{ margin: 0, fontSize: '28px', fontWeight: '800' }}>
              Admin Dashboard
            </h1>
          </div>
        </div>
      </div>

      {/* TOP ROW - Stats Cards Grid (3 columns) */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(3, 1fr)',        
        gap: '20px',
        marginBottom: '32px'
      }}>
        {/* Pending Coach Approvals Card */}
        <div style={{
          backgroundColor: 'white',
          padding: '24px',
          borderRadius: '16px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #f3f4f6',
          cursor: 'pointer',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
          position: 'relative',
          overflow: 'hidden'
        }}
        onClick={() => setCurrentPage('coachApproval')}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'translateY(-4px)';
          e.currentTarget.style.boxShadow = '0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)';
          e.currentTarget.style.borderColor = '#FF8A50';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'translateY(0)';
          e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)';
          e.currentTarget.style.borderColor = '#f3f4f6';
        }}>
          <div style={{
            position: 'absolute',
            top: '-20px',
            right: '-20px',
            width: '100px',
            height: '100px',
            background: 'linear-gradient(135deg, #fef3e2 0%, #ffe8cc 100%)',
            borderRadius: '50%',
            opacity: 0.5
          }} />
          
          <div style={{ position: 'relative', zIndex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '16px' }}>
              <div>
                <p style={{ margin: '0 0 4px 0', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Coach Approvals
                </p>
                <h3 style={{ margin: 0, fontSize: '36px', fontWeight: '800', color: '#1f2937', lineHeight: '1' }}>
                  {pendingCoachCount}
                </h3>
              </div>
              <div style={{
                width: '48px',
                height: '48px',
                background: 'linear-gradient(135deg, #FF8A50 0%, #FF6B35 100%)',
                borderRadius: '12px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 4px 12px rgba(255, 138, 80, 0.3)'
              }}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="white">
                  <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
                </svg>
              </div>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{
                padding: '4px 10px',
                background: pendingCoachCount > 0 ? '#fef3e2' : '#d1fae5',
                borderRadius: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px'
              }}>
                <div style={{
                  width: '6px',
                  height: '6px',
                  background: pendingCoachCount > 0 ? '#f59e0b' : '#10b981',
                  borderRadius: '50%',
                  animation: pendingCoachCount > 0 ? 'pulse 2s infinite' : 'none'
                }} />
                <span style={{ 
                  fontSize: '12px', 
                  fontWeight: '600',
                  color: pendingCoachCount > 0 ? '#d97706' : '#059669'
                }}>
                  {pendingCoachCount > 0 ? 'Pending Review' : 'All Clear'}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Pending Venue Approvals Card */}
        <div style={{
          backgroundColor: 'white',
          padding: '24px',
          borderRadius: '16px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #f3f4f6',
          cursor: 'pointer',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
          position: 'relative',
          overflow: 'hidden'
        }}
        onClick={() => setCurrentPage('venueApproval')}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'translateY(-4px)';
          e.currentTarget.style.boxShadow = '0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)';
          e.currentTarget.style.borderColor = '#10b981';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'translateY(0)';
          e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)';
          e.currentTarget.style.borderColor = '#f3f4f6';
        }}>
          <div style={{
            position: 'absolute',
            top: '-20px',
            right: '-20px',
            width: '100px',
            height: '100px',
            background: 'linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%)',
            borderRadius: '50%',
            opacity: 0.5
          }} />
          
          <div style={{ position: 'relative', zIndex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '16px' }}>
              <div>
                <p style={{ margin: '0 0 4px 0', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Venue Approvals
                </p>
                <h3 style={{ margin: 0, fontSize: '36px', fontWeight: '800', color: '#1f2937', lineHeight: '1' }}>
                  {pendingVenueCount}
                </h3>
              </div>
              <div style={{
                width: '48px',
                height: '48px',
                background: 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
                borderRadius: '12px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 4px 12px rgba(16, 185, 129, 0.3)'
              }}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="white">
                  <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V7.3l7-3.11v8.8z"/>
                </svg>
              </div>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{
                padding: '4px 10px',
                background: pendingVenueCount > 0 ? '#fef3e2' : '#d1fae5',
                borderRadius: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px'
              }}>
                <div style={{
                  width: '6px',
                  height: '6px',
                  background: pendingVenueCount > 0 ? '#f59e0b' : '#10b981',
                  borderRadius: '50%',
                  animation: pendingVenueCount > 0 ? 'pulse 2s infinite' : 'none'
                }} />
                <span style={{ 
                  fontSize: '12px', 
                  fontWeight: '600',
                  color: pendingVenueCount > 0 ? '#d97706' : '#059669'
                }}>
                  {pendingVenueCount > 0 ? 'Pending Review' : 'All Clear'}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Total Users Card */}
        <div style={{
          backgroundColor: 'white',
          padding: '24px',
          borderRadius: '16px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #f3f4f6',
          cursor: 'pointer',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
          position: 'relative',
          overflow: 'hidden'
        }}
        onClick={() => setCurrentPage('userManagement')}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'translateY(-4px)';
          e.currentTarget.style.boxShadow = '0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)';
          e.currentTarget.style.borderColor = '#8b5cf6';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'translateY(0)';
          e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)';
          e.currentTarget.style.borderColor = '#f3f4f6';
        }}>
          <div style={{
            position: 'absolute',
            top: '-20px',
            right: '-20px',
            width: '100px',
            height: '100px',
            background: 'linear-gradient(135deg, #ede9fe 0%, #ddd6fe 100%)',
            borderRadius: '50%',
            opacity: 0.5
          }} />
          
          <div style={{ position: 'relative', zIndex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '16px' }}>
              <div>
                <p style={{ margin: '0 0 4px 0', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Total Users
                </p>
                <h3 style={{ margin: 0, fontSize: '36px', fontWeight: '800', color: '#1f2937', lineHeight: '1' }}>
                  {totalUserCount}
                </h3>
              </div>
              <div style={{
                width: '48px',
                height: '48px',
                background: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
                borderRadius: '12px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 4px 12px rgba(139, 92, 246, 0.3)'
              }}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="white">
                  <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
                </svg>
              </div>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{
                padding: '4px 10px',
                background: '#ede9fe',
                borderRadius: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px'
              }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="#7c3aed">
                  <path d="M16 6l2.29 2.29-4.88 4.88-4-4L2 16.59 3.41 18l6-6 4 4 6.3-6.29L22 12V6z"/>
                </svg>
                <span style={{ 
                  fontSize: '12px', 
                  fontWeight: '600',
                  color: '#6d28d9'
                }}>
                  Active Platform
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* BOTTOM ROW - 2 Cards Grid (2 columns) */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(2, 1fr)',
        gap: '20px',
        marginBottom: '32px'
      }}>
        {/* Coach Payment Card */}
        <div style={{
          backgroundColor: 'white',
          padding: '24px',
          borderRadius: '16px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #f3f4f6',
          cursor: 'pointer',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
          position: 'relative',
          overflow: 'hidden'
        }}
        onClick={() => setCurrentPage('sessionVerification')}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'translateY(-4px)';
          e.currentTarget.style.boxShadow = '0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)';
          e.currentTarget.style.borderColor = '#f59e0b';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'translateY(0)';
          e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)';
          e.currentTarget.style.borderColor = '#f3f4f6';
        }}>
          <div style={{
            position: 'absolute',
            top: '-20px',
            right: '-20px',
            width: '100px',
            height: '100px',
            background: 'linear-gradient(135deg, #fef3e2 0%, #fed7aa 100%)',
            borderRadius: '50%',
            opacity: 0.5
          }} />
          
          <div style={{ position: 'relative', zIndex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '16px' }}>
              <div>
                <p style={{ margin: '0 0 4px 0', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Coach Payment
                </p>
                <h3 style={{ margin: 0, fontSize: '36px', fontWeight: '800', color: '#1f2937', lineHeight: '1' }}>
                  {pendingVerificationCount}
                </h3>
              </div>
              <div style={{
                width: '48px',
                height: '48px',
                background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
                borderRadius: '12px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 4px 12px rgba(245, 158, 11, 0.3)'
              }}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="white">
                  <path d="M21 6h-2v9H6v2c0 .55.45 1 1 1h11l4 4V7c0-.55-.45-1-1-1zm-4 6V3c0-.55-.45-1-1-1H3c-.55 0-1 .45-1 1v14l4-4h10c.55 0 1-.45 1-1z"/>
                </svg>
              </div>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{
                padding: '4px 10px',
                background: pendingVerificationCount > 0 ? '#fef3e2' : '#d1fae5',
                borderRadius: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px'
              }}>
                <div style={{
                  width: '6px',
                  height: '6px',
                  background: pendingVerificationCount > 0 ? '#f59e0b' : '#10b981',
                  borderRadius: '50%',
                  animation: pendingVerificationCount > 0 ? 'pulse 2s infinite' : 'none'
                }} />
                <span style={{ 
                  fontSize: '12px', 
                  fontWeight: '600',
                  color: pendingVerificationCount > 0 ? '#d97706' : '#059669'
                }}>
                  {pendingVerificationCount > 0 ? 'Needs Review' : 'All Verified'}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Venue Payment Card */}
        <div style={{
          backgroundColor: 'white',
          padding: '24px',
          borderRadius: '16px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #f3f4f6',
          cursor: 'pointer',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
          position: 'relative',
          overflow: 'hidden'
        }}
        onClick={() => setCurrentPage('paymentManagement')}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'translateY(-4px)';
          e.currentTarget.style.boxShadow = '0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)';
          e.currentTarget.style.borderColor = '#3b82f6';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'translateY(0)';
          e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.06)';
          e.currentTarget.style.borderColor = '#f3f4f6';
        }}>
          <div style={{
            position: 'absolute',
            top: '-20px',
            right: '-20px',
            width: '100px',
            height: '100px',
            background: 'linear-gradient(135deg, #dbeafe 0%, #bfdbfe 100%)',
            borderRadius: '50%',
            opacity: 0.5
          }} />
          
          <div style={{ position: 'relative', zIndex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '16px' }}>
              <div>
                <p style={{ margin: '0 0 4px 0', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Venue Payment
                </p>
                <h3 style={{ margin: 0, fontSize: '36px', fontWeight: '800', color: '#1f2937', lineHeight: '1' }}>
                  {pendingVenueCount}
                </h3>
              </div>
              <div style={{
                width: '48px',
                height: '48px',
                background: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)',
                borderRadius: '12px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 4px 12px rgba(59, 130, 246, 0.3)'
              }}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="white">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1.41 16.09V20h-2.67v-1.93c-1.71-.36-3.16-1.46-3.27-3.4h1.96c.1 1.05.82 1.87 2.65 1.87 1.96 0 2.4-.98 2.4-1.59 0-.83-.44-1.61-2.67-2.14-2.48-.6-4.18-1.62-4.18-3.67 0-1.72 1.39-2.84 3.11-3.21V4h2.67v1.95c1.86.45 2.79 1.86 2.85 3.39H14.3c-.05-1.11-.64-1.87-2.22-1.87-1.5 0-2.4.68-2.4 1.64 0 .84.65 1.39 2.67 1.91s4.18 1.39 4.18 3.91c-.01 1.83-1.38 2.83-3.12 3.16z"/>
                </svg>
              </div>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{
                padding: '4px 10px',
                background: '#dbeafe',
                borderRadius: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '4px'
              }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="#2563eb">
                  <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
                </svg>
                <span style={{ 
                  fontSize: '12px', 
                  fontWeight: '600',
                  color: '#1e40af'
                }}>
                  Manage Payments
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Add pulse animation */}
      <style>{`
        @keyframes pulse {
          0%, 100% {
            opacity: 1;
          }
          50% {
            opacity: 0.5;
          }
        }
      `}</style>
    </>
  );

  return (
    <div style={{
      minHeight: '100vh',
      backgroundColor: '#f9fafb'
    }}>
      {/* Header */}
      <header style={{
        backgroundColor: 'white',
        padding: '16px 32px',
        borderBottom: '1px solid #e5e7eb',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        boxShadow: '0 1px 3px rgba(0,0,0,0.1)',
        position: 'sticky',
        top: 0,
        zIndex: 100
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '20px' }}>
          {/* Logo */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{
              width: '40px',
              height: '40px',
              background: 'linear-gradient(135deg, #FF8A50 0%, #FF6B35 100%)',
              borderRadius: '10px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 4px 12px rgba(255, 138, 80, 0.3)'
            }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="white">
                <path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/>
              </svg>
            </div>
            <div>
              <h1 style={{
                fontSize: '20px',
                fontWeight: '800',
                color: '#1f2937',
                margin: 0,
                lineHeight: '1',
                letterSpacing: '0.3px'
              }}>
                SPORTIFY
              </h1>
              <p style={{
                fontSize: '11px',
                color: '#6b7280',
                margin: '2px 0 0 0',
                fontWeight: '600',
                textTransform: 'uppercase',
                letterSpacing: '0.5px'
              }}>
                Admin Portal
              </p>
            </div>
          </div>
          
          {/* Breadcrumb */}
          {currentPage !== 'dashboard' && (
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginLeft: '12px' }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="#d1d5db">
                <path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/>
              </svg>
              <button
                onClick={() => setCurrentPage('dashboard')}
                style={{
                  background: 'none',
                  border: 'none',
                  color: '#3b82f6',
                  cursor: 'pointer',
                  fontSize: '14px',
                  fontWeight: '600',
                  padding: '4px 8px',
                  borderRadius: '6px',
                  transition: 'all 0.2s ease'
                }}
                onMouseEnter={(e) => {
                  e.target.style.background = '#eff6ff';
                }}
                onMouseLeave={(e) => {
                  e.target.style.background = 'none';
                }}
              >
                Dashboard
              </button>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="#d1d5db">
                <path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/>
              </svg>
              <span style={{ color: '#6b7280', fontSize: '14px', fontWeight: '600' }}>
                {currentPage === 'coachApproval' ? 'Coach Applications' : 
                 currentPage === 'venueApproval' ? 'Venue Applications' : 
                 currentPage === 'userManagement' ? 'User Management' : 
                 currentPage === 'sessionVerification' ? 'Session Verifications' : currentPage}
              </span>
            </div>
          )}
        </div>
        
        {/* Right Side */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          {/* User Info */}
          <div style={{ 
            display: 'flex', 
            alignItems: 'center', 
            gap: '12px',
            padding: '8px 16px',
            background: '#f9fafb',
            borderRadius: '10px',
            border: '1px solid #e5e7eb'
          }}>
            <div style={{
              width: '32px',
              height: '32px',
              background: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)',
              borderRadius: '8px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontWeight: '700',
              color: 'white',
              fontSize: '14px'
            }}>
              {(user?.name || user?.email || 'A')[0].toUpperCase()}
            </div>
            <div>
              <p style={{ 
                margin: 0, 
                fontSize: '13px', 
                fontWeight: '600', 
                color: '#1f2937',
                lineHeight: '1'
              }}>
                {user?.name || 'Admin'}
              </p>
              <p style={{ 
                margin: '2px 0 0 0', 
                fontSize: '11px', 
                color: '#6b7280',
                lineHeight: '1'
              }}>
                Administrator
              </p>
            </div>
          </div>

          {/* Logout Button */}
          <button
            onClick={handleLogout}
            style={{
              padding: '10px 20px',
              background: 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)',
              color: 'white',
              border: 'none',
              borderRadius: '10px',
              cursor: 'pointer',
              fontSize: '14px',
              fontWeight: '600',
              transition: 'all 0.3s ease',
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              boxShadow: '0 4px 12px rgba(239, 68, 68, 0.3)'
            }}
            onMouseEnter={(e) => {
              e.target.style.transform = 'translateY(-2px)';
              e.target.style.boxShadow = '0 8px 20px rgba(239, 68, 68, 0.4)';
            }}
            onMouseLeave={(e) => {
              e.target.style.transform = 'translateY(0)';
              e.target.style.boxShadow = '0 4px 12px rgba(239, 68, 68, 0.3)';
            }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
            </svg>
            Logout
          </button>
        </div>
      </header>

      {/* Main Content */}
      <main style={{ padding: '32px' }}>
        {currentPage === 'dashboard' && renderDashboard()}
        {currentPage === 'coachApproval' && <CoachApprovalPage />}
        {currentPage === 'venueApproval' && <VenueApprovalPage />}
        {currentPage === 'userManagement' && <UserManagementPage />}
        {currentPage === 'sessionVerification' && <SessionVerificationPage />}
        {currentPage === 'paymentManagement' && <AdminPaymentManagement />}
      </main>
    </div>
  );
};

export default AdminDashboard;
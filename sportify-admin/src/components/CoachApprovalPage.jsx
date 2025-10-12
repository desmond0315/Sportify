import React, { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, doc, updateDoc, setDoc, getDoc } from 'firebase/firestore';
import { db } from '../firebase';
import EmailService from '../services/EmailService';

const CoachApprovalPage = () => {
  const [pendingCoaches, setPendingCoaches] = useState([]);
  const [selectedCoach, setSelectedCoach] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [filter, setFilter] = useState('pending');
  const [emailStatus, setEmailStatus] = useState({ show: false, message: '', type: '' });

  useEffect(() => {
    const fetchApplications = () => {
      let q;
      if (filter === 'all') {
        q = query(collection(db, 'coach_applications'));
      } else {
        q = query(collection(db, 'coach_applications'), where('status', '==', filter));
      }

      const unsubscribe = onSnapshot(q, (querySnapshot) => {
        const applications = [];
        querySnapshot.forEach((doc) => {
          applications.push({ id: doc.id, ...doc.data() });
        });
        
        applications.sort((a, b) => {
          if (a.createdAt && b.createdAt) {
            return b.createdAt.toDate() - a.createdAt.toDate();
          }
          return 0;
        });
        
        setPendingCoaches(applications);
        setIsLoading(false);
      });

      return unsubscribe;
    };

    const unsubscribe = fetchApplications();
    return () => unsubscribe();
  }, [filter]);

  const showEmailStatus = (message, type) => {
    setEmailStatus({ show: true, message, type });
    setTimeout(() => {
      setEmailStatus({ show: false, message: '', type: '' });
    }, 5000);
  };

  const handleApproveCoach = async (applicationId) => {
    setIsProcessing(true);
    try {
      const application = pendingCoaches.find(c => c.id === applicationId);
      
      const coachDocId = application.userId || applicationId;
      
      if (!application.userId) {
        alert('Error: No Firebase Auth UID found for this application. Cannot approve.');
        setIsProcessing(false);
        return;
      }
      
      const coachData = {
        ...application,
        status: 'approved',
        isVerified: true,
        isActive: true,
        approvedAt: new Date(),
        updatedAt: new Date()
      };
      
      await setDoc(doc(db, 'coaches', application.userId), coachData);
      
      await updateDoc(doc(db, 'coach_applications', applicationId), {
        status: 'approved',
        approvedAt: new Date(),
        updatedAt: new Date()
      });

      if (application.hasAccount && application.userId) {
        try {
          const userDoc = await getDoc(doc(db, 'users', application.userId));
          if (userDoc.exists()) {
            await updateDoc(doc(db, 'users', application.userId), {
              role: 'coach',
              isActive: true,
              updatedAt: new Date()
            });
          }
        } catch (userError) {
          console.log('User document not found or error updating:', userError);
        }
      }

      const coachEmailData = {
        ownerName: application.name,
        venueName: `${application.sport} Coach`,
        email: application.email
      };

      const emailResult = await EmailService.sendApprovalEmail(coachEmailData, null);
      
      if (emailResult.success) {
        showEmailStatus('Coach approved and email notification sent successfully!', 'success');
        alert('Coach approved successfully and notification email sent!');
      } else {
        showEmailStatus('Coach approved but email notification failed to send.', 'warning');
        alert('Coach approved successfully, but the email notification failed to send. Please manually contact the coach.');
      }

      setSelectedCoach(null);
    } catch (error) {
      console.error('Error approving coach:', error);
      showEmailStatus('Error approving coach. Please try again.', 'error');
      alert('Error approving coach. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleRejectCoach = async (applicationId, reason = '') => {
    const rejectionReason = reason || prompt('Please provide a reason for rejection (optional):') || 'Application did not meet requirements';
    const confirmReject = window.confirm(`Are you sure you want to reject this coach application?\n\nReason: ${rejectionReason}`);
    if (!confirmReject) return;

    setIsProcessing(true);
    try {
      const application = pendingCoaches.find(c => c.id === applicationId);
      
      await updateDoc(doc(db, 'coach_applications', applicationId), {
        status: 'rejected',
        isVerified: false,
        isActive: false,
        rejectedAt: new Date(),
        rejectionReason: rejectionReason,
        updatedAt: new Date()
      });

      const coachEmailData = {
        ownerName: application.name,
        venueName: `${application.sport} Coach`,
        email: application.email
      };

      const emailResult = await EmailService.sendRejectionEmail(coachEmailData, rejectionReason);
      
      if (emailResult.success) {
        showEmailStatus('Coach rejected and email notification sent successfully!', 'success');
        alert('Coach application rejected and notification email sent.');
      } else {
        showEmailStatus('Coach rejected but email notification failed to send.', 'warning');
        alert('Coach application rejected, but the email notification failed to send. Please manually contact the coach.');
      }

      setSelectedCoach(null);
    } catch (error) {
      console.error('Error rejecting coach:', error);
      showEmailStatus('Error rejecting coach. Please try again.', 'error');
      alert('Error rejecting coach. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const formatDate = (timestamp) => {
    if (!timestamp) return 'N/A';
    try {
      return timestamp.toDate().toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch (error) {
      return 'N/A';
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'pending': return '#f59e0b';
      case 'approved': return '#10b981';
      case 'rejected': return '#ef4444';
      default: return '#6b7280';
    }
  };

  const renderImagePreview = (base64String, alt = 'Image') => {
    if (!base64String) return null;
    
    try {
      const imageSrc = base64String.startsWith('data:') 
        ? base64String 
        : `data:image/jpeg;base64,${base64String}`;
      
      return (
        <img 
          src={imageSrc} 
          alt={alt}
          style={{
            maxWidth: '100%',
            maxHeight: '300px',
            objectFit: 'contain',
            borderRadius: '8px',
            border: '1px solid #e5e7eb'
          }}
          onError={(e) => {
            e.target.style.display = 'none';
          }}
        />
      );
    } catch (error) {
      return <div style={{ color: '#ef4444' }}>Error loading image</div>;
    }
  };

  if (isLoading) {
    return (
      <div style={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #f8fafc 0%, #fff5f0 50%, #f8fafc 100%)',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
      }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{
            width: '56px',
            height: '56px',
            border: '4px solid #fed7aa',
            borderTop: '4px solid #ff8a50',
            borderRadius: '50%',
            animation: 'spin 0.8s linear infinite',
            margin: '0 auto 20px'
          }} />
          <p style={{ color: '#64748b', fontSize: '16px', fontWeight: '600' }}>Loading coach applications...</p>
          <style>{`
            @keyframes spin {
              0% { transform: rotate(0deg); }
              100% { transform: rotate(360deg); }
            }
          `}</style>
        </div>
      </div>
    );
  }

  return (
    <div style={{
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      padding: '32px',
      background: 'linear-gradient(135deg, #f8fafc 0%, #fff5f0 50%, #f8fafc 100%)',
      minHeight: '100vh'
    }}>
      {emailStatus.show && (
        <div style={{
          position: 'fixed',
          top: '24px',
          right: '24px',
          zIndex: 1000,
          padding: '18px 24px',
          borderRadius: '16px',
          boxShadow: '0 20px 40px rgba(0, 0, 0, 0.15)',
          background: emailStatus.type === 'success' ? 'linear-gradient(135deg, #10b981 0%, #059669 100%)' : 
                     emailStatus.type === 'warning' ? 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)' : 
                     'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)',
          color: 'white',
          fontWeight: '600',
          maxWidth: '420px',
          animation: 'slideInRight 0.4s cubic-bezier(0.16, 1, 0.3, 1)'
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{ 
              width: '32px', 
              height: '32px', 
              background: 'rgba(255,255,255,0.2)', 
              borderRadius: '8px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
              fontSize: '18px'
            }}>
              {emailStatus.type === 'success' ? '✓' : emailStatus.type === 'warning' ? '⚠' : '✕'}
            </div>
            <span style={{ fontSize: '15px', lineHeight: '1.5' }}>{emailStatus.message}</span>
          </div>
          <style>{`
            @keyframes slideInRight {
              from { transform: translateX(100%); opacity: 0; }
              to { transform: translateX(0); opacity: 1; }
            }
          `}</style>
        </div>
      )}

      <div style={{ marginBottom: '32px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '12px' }}>
          <div style={{
            width: '56px',
            height: '56px',
            background: 'linear-gradient(135deg, #ff8a50 0%, #ff6b35 100%)',
            borderRadius: '16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            boxShadow: '0 10px 30px rgba(255, 138, 80, 0.3)'
          }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="white">
              <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
            </svg>
          </div>
          <div>
            <h1 style={{ 
              fontSize: '32px', 
              fontWeight: '800', 
              color: '#0f172a',
              margin: '0 0 4px 0',
              letterSpacing: '-0.5px'
            }}>
              Coach Applications
            </h1>
            <p style={{ color: '#64748b', margin: 0, fontSize: '15px', fontWeight: '500' }}>
              Review and approve coach registrations
            </p>
          </div>
        </div>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
        gap: '20px',
        marginBottom: '32px'
      }}>
        {[
          { key: 'pending', label: 'Pending', count: pendingCoaches.filter(c => c.status === 'pending').length, gradient: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)', icon: '⏳' },
          { key: 'approved', label: 'Approved', count: pendingCoaches.filter(c => c.status === 'approved').length, gradient: 'linear-gradient(135deg, #10b981 0%, #059669 100%)', icon: '✓' },
          { key: 'rejected', label: 'Rejected', count: pendingCoaches.filter(c => c.status === 'rejected').length, gradient: 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)', icon: '✕' },
          { key: 'all', label: 'Total', count: pendingCoaches.length, gradient: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)', icon: '📋' }
        ].map(({ key, label, count, gradient, icon }) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            style={{
              position: 'relative',
              padding: '24px',
              background: 'white',
              borderRadius: '20px',
              border: filter === key ? '3px solid #ff8a50' : '3px solid transparent',
              cursor: 'pointer',
              transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
              boxShadow: filter === key 
                ? '0 20px 40px rgba(255, 138, 80, 0.15)' 
                : '0 4px 12px rgba(0, 0, 0, 0.08)',
              transform: filter === key ? 'translateY(-4px)' : 'translateY(0)',
              overflow: 'hidden'
            }}
            onMouseEnter={(e) => {
              if (filter !== key) {
                e.currentTarget.style.transform = 'translateY(-2px)';
                e.currentTarget.style.boxShadow = '0 12px 24px rgba(0, 0, 0, 0.12)';
              }
            }}
            onMouseLeave={(e) => {
              if (filter !== key) {
                e.currentTarget.style.transform = 'translateY(0)';
                e.currentTarget.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.08)';
              }
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ textAlign: 'left' }}>
                <p style={{ 
                  margin: '0 0 8px 0', 
                  fontSize: '12px', 
                  fontWeight: '700', 
                  color: '#64748b', 
                  textTransform: 'uppercase', 
                  letterSpacing: '1px' 
                }}>
                  {label}
                </p>
                <p style={{ 
                  margin: 0, 
                  fontSize: '36px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  lineHeight: '1'
                }}>
                  {count}
                </p>
              </div>
              <div style={{
                width: '56px',
                height: '56px',
                background: gradient,
                borderRadius: '16px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '24px',
                boxShadow: '0 8px 20px rgba(0, 0, 0, 0.15)'
              }}>
                {icon}
              </div>
            </div>
            {filter === key && (
              <div style={{
                position: 'absolute',
                bottom: 0,
                left: 0,
                right: 0,
                height: '4px',
                background: 'linear-gradient(90deg, #ff8a50, #ff6b35)',
                borderRadius: '0 0 17px 17px'
              }} />
            )}
          </button>
        ))}
      </div>

      <div style={{ display: 'flex', gap: '24px' }}>
        <div style={{ flex: '1', maxWidth: selectedCoach ? '420px' : '100%' }}>
          {pendingCoaches.length === 0 ? (
            <div style={{
              textAlign: 'center',
              padding: '64px 32px',
              background: 'white',
              borderRadius: '24px',
              boxShadow: '0 4px 20px rgba(0, 0, 0, 0.08)',
              border: '2px solid #f1f5f9'
            }}>
              <div style={{ fontSize: '64px', marginBottom: '20px' }}></div>
              <h3 style={{ color: '#475569', margin: '0 0 12px 0', fontSize: '20px', fontWeight: '700' }}>
                No {filter} applications
              </h3>
              <p style={{ color: '#94a3b8', margin: 0, fontSize: '15px' }}>
                {filter === 'pending' 
                  ? 'New coach applications will appear here'
                  : `No ${filter} coach applications found`
                }
              </p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {pendingCoaches.map((coach) => (
                <div
                  key={coach.id}
                  onClick={() => setSelectedCoach(coach)}
                  style={{
                    padding: '20px',
                    background: 'white',
                    borderRadius: '20px',
                    cursor: 'pointer',
                    boxShadow: selectedCoach?.id === coach.id 
                      ? '0 12px 32px rgba(255, 138, 80, 0.2)' 
                      : '0 4px 12px rgba(0, 0, 0, 0.06)',
                    border: selectedCoach?.id === coach.id ? '3px solid #ff8a50' : '3px solid transparent',
                    transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
                    transform: selectedCoach?.id === coach.id ? 'translateY(-2px)' : 'translateY(0)'
                  }}
                  onMouseEnter={(e) => {
                    if (selectedCoach?.id !== coach.id) {
                      e.currentTarget.style.boxShadow = '0 8px 20px rgba(0, 0, 0, 0.1)';
                      e.currentTarget.style.borderColor = '#ffeedd';
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (selectedCoach?.id !== coach.id) {
                      e.currentTarget.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.06)';
                      e.currentTarget.style.borderColor = 'transparent';
                    }
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                    <div style={{
                      position: 'relative',
                      width: '64px',
                      height: '64px',
                      borderRadius: '16px',
                      background: '#f1f5f9',
                      overflow: 'hidden',
                      flexShrink: 0,
                      boxShadow: '0 4px 12px rgba(0, 0, 0, 0.1)'
                    }}>
                      {coach.profileImageBase64 ? (
                        <img 
                          src={coach.profileImageBase64.startsWith('data:') 
                            ? coach.profileImageBase64 
                            : `data:image/jpeg;base64,${coach.profileImageBase64}`
                          }
                          alt="Profile"
                          style={{
                            width: '100%',
                            height: '100%',
                            objectFit: 'cover'
                          }}
                          onError={(e) => {
                            e.target.style.display = 'none';
                          }}
                        />
                      ) : (
                        <div style={{ 
                          width: '100%',
                          height: '100%',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          fontSize: '28px',
                          color: '#94a3b8'
                        }}>👤</div>
                      )}
                      
                      <div style={{
                        position: 'absolute',
                        bottom: '-4px',
                        right: '-4px',
                        width: '24px',
                        height: '24px',
                        background: 'white',
                        borderRadius: '8px',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        boxShadow: '0 2px 8px rgba(0,0,0,0.15)',
                        fontSize: '12px'
                      }}>
                        {coach.status === 'pending' ? '⏳' : coach.status === 'approved' ? '✓' : '✕'}
                      </div>
                    </div>

                    <div style={{ flex: 1, minWidth: 0 }}>
                      <h3 style={{ 
                        margin: '0 0 6px 0', 
                        fontSize: '17px', 
                        fontWeight: '700',
                        color: '#0f172a',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap'
                      }}>
                        {coach.name}
                      </h3>
                      <p style={{ 
                        margin: '0 0 6px 0', 
                        fontSize: '14px', 
                        color: '#64748b',
                        fontWeight: '500'
                      }}>
                         {coach.sport} •  {coach.location}
                      </p>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                        <span style={{
                          padding: '4px 12px',
                          borderRadius: '8px',
                          background: coach.status === 'pending' ? '#fef3e2' : 
                                     coach.status === 'approved' ? '#d1fae5' : '#fee2e2',
                          color: coach.status === 'pending' ? '#d97706' : 
                                 coach.status === 'approved' ? '#059669' : '#dc2626',
                          fontSize: '11px',
                          fontWeight: '700',
                          textTransform: 'uppercase',
                          letterSpacing: '0.5px'
                        }}>
                          {coach.status}
                        </span>
                        <span style={{ 
                          fontSize: '12px', 
                          color: '#94a3b8',
                          fontWeight: '500'
                        }}>
                          {formatDate(coach.createdAt)}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {selectedCoach && (
          <div style={{
            flex: '2',
            background: 'white',
            borderRadius: '24px',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.12)',
            overflow: 'hidden',
            border: '1px solid #f1f5f9'
          }}>
            <div style={{
              padding: '32px',
              background: 'linear-gradient(135deg, #ff8a50 0%, #ff6b35 100%)',
              position: 'relative',
              overflow: 'hidden'
            }}>
              <div style={{
                position: 'absolute',
                top: '-40px',
                right: '-40px',
                width: '160px',
                height: '160px',
                background: 'rgba(255, 255, 255, 0.1)',
                borderRadius: '50%'
              }} />
              <div style={{
                position: 'absolute',
                bottom: '-20px',
                left: '-20px',
                width: '120px',
                height: '120px',
                background: 'rgba(0, 0, 0, 0.1)',
                borderRadius: '50%'
              }} />
              
              <div style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: '20px' }}>
                <div style={{
                  width: '96px',
                  height: '96px',
                  borderRadius: '20px',
                  background: 'rgba(255, 255, 255, 0.2)',
                  overflow: 'hidden',
                  boxShadow: '0 8px 24px rgba(0, 0, 0, 0.2)',
                  border: '4px solid rgba(255, 255, 255, 0.3)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center'
                }}>
                  {selectedCoach.profileImageBase64 ? (
                    <img 
                      src={selectedCoach.profileImageBase64.startsWith('data:') 
                        ? selectedCoach.profileImageBase64 
                        : `data:image/jpeg;base64,${selectedCoach.profileImageBase64}`
                      }
                      alt="Profile"
                      style={{
                        width: '100%',
                        height: '100%',
                        objectFit: 'cover'
                      }}
                    />
                  ) : (
                    <div style={{ fontSize: '48px', color: 'white' }}>👤</div>
                  )}
                </div>
                <div style={{ flex: 1 }}>
                  <h2 style={{ 
                    margin: '0 0 8px 0', 
                    fontSize: '28px', 
                    fontWeight: '800',
                    color: 'white',
                    letterSpacing: '-0.5px'
                  }}>
                    {selectedCoach.name}
                  </h2>
                  <p style={{ 
                    margin: '0 0 12px 0', 
                    fontSize: '16px', 
                    color: 'rgba(255, 255, 255, 0.95)',
                    fontWeight: '600'
                  }}>
                    {selectedCoach.sport} Coach • {selectedCoach.experience}
                  </p>
                  <div style={{
                    display: 'inline-block',
                    padding: '8px 16px',
                    borderRadius: '12px',
                    background: 'rgba(255, 255, 255, 0.2)',
                    backdropFilter: 'blur(10px)',
                    color: 'white',
                    fontSize: '13px',
                    fontWeight: '700',
                    textTransform: 'capitalize',
                    border: '2px solid rgba(255, 255, 255, 0.3)'
                  }}>
                    {selectedCoach.status}
                  </div>
                </div>
              </div>
            </div>

            <div style={{ padding: '32px', maxHeight: '65vh', overflowY: 'auto' }}>
              <div style={{ marginBottom: '28px' }}>
                <h3 style={{ 
                  fontSize: '14px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  margin: '0 0 16px 0',
                  textTransform: 'uppercase',
                  letterSpacing: '1px'
                }}>
                   Contact Information
                </h3>
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', 
                  gap: '16px',
                  padding: '20px',
                  background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
                  borderRadius: '16px',
                  border: '2px solid #e2e8f0'
                }}>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Email
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedCoach.email}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Phone
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedCoach.phone || 'Not provided'}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Location
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedCoach.location}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Price per Hour
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '18px', color: '#ff8a50', fontWeight: '800' }}>
                      RM {selectedCoach.pricePerHour}
                    </p>
                  </div>
                </div>
              </div>

              <div style={{ marginBottom: '28px' }}>
                <h3 style={{ 
                  fontSize: '14px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  margin: '0 0 12px 0',
                  textTransform: 'uppercase',
                  letterSpacing: '1px'
                }}>
                  About
                </h3>
                <p style={{ 
                  margin: 0, 
                  fontSize: '15px', 
                  color: '#475569',
                  lineHeight: '1.7',
                  background: 'linear-gradient(135deg, #fafafa 0%, #f5f5f5 100%)',
                  padding: '20px',
                  borderRadius: '16px',
                  border: '2px solid #e5e7eb',
                  fontWeight: '500'
                }}>
                  {selectedCoach.bio || 'No bio provided'}
                </p>
              </div>

              {selectedCoach.specialties && selectedCoach.specialties.length > 0 && (
                <div style={{ marginBottom: '28px' }}>
                  <h3 style={{ 
                    fontSize: '14px', 
                    fontWeight: '800', 
                    color: '#0f172a',
                    margin: '0 0 12px 0',
                    textTransform: 'uppercase',
                    letterSpacing: '1px'
                  }}>
                    Specialties
                  </h3>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px' }}>
                    {selectedCoach.specialties.map((specialty, index) => (
                      <span
                        key={index}
                        style={{
                          padding: '10px 18px',
                          background: 'linear-gradient(135deg, #e0f2fe 0%, #bae6fd 100%)',
                          color: '#0369a1',
                          borderRadius: '12px',
                          fontSize: '13px',
                          fontWeight: '700',
                          border: '2px solid #7dd3fc',
                          boxShadow: '0 2px 8px rgba(14, 165, 233, 0.2)'
                        }}
                      >
                        {specialty}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              <div style={{ marginBottom: '28px' }}>
                <h3 style={{ 
                  fontSize: '14px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  margin: '0 0 16px 0',
                  textTransform: 'uppercase',
                  letterSpacing: '1px'
                }}>
                  Submitted Documents
                </h3>
                
                {selectedCoach.licenseBase64 && (
                  <div style={{ 
                    marginBottom: '20px',
                    padding: '20px',
                    background: 'white',
                    borderRadius: '16px',
                    border: '2px solid #e2e8f0',
                    boxShadow: '0 4px 12px rgba(0, 0, 0, 0.05)'
                  }}>
                    <h4 style={{ 
                      fontSize: '14px', 
                      fontWeight: '700', 
                      margin: '0 0 12px 0', 
                      color: '#475569'
                    }}>
                       Coaching License
                      {selectedCoach.licenseFileName && (
                        <span style={{ fontWeight: '400', color: '#94a3b8', fontSize: '12px', marginLeft: '8px' }}>
                          ({selectedCoach.licenseFileName})
                        </span>
                      )}
                    </h4>
                    {renderImagePreview(selectedCoach.licenseBase64, 'Coaching License')}
                  </div>
                )}

                {selectedCoach.certificateBase64 && (
                  <div style={{ 
                    marginBottom: '20px',
                    padding: '20px',
                    background: 'white',
                    borderRadius: '16px',
                    border: '2px solid #e2e8f0',
                    boxShadow: '0 4px 12px rgba(0, 0, 0, 0.05)'
                  }}>
                    <h4 style={{ 
                      fontSize: '14px', 
                      fontWeight: '700', 
                      margin: '0 0 12px 0', 
                      color: '#475569'
                    }}>
                       Certificate
                      {selectedCoach.certificateFileName && (
                        <span style={{ fontWeight: '400', color: '#94a3b8', fontSize: '12px', marginLeft: '8px' }}>
                          ({selectedCoach.certificateFileName})
                        </span>
                      )}
                    </h4>
                    {renderImagePreview(selectedCoach.certificateBase64, 'Certificate')}
                  </div>
                )}

                {!selectedCoach.licenseBase64 && !selectedCoach.certificateBase64 && (
                  <p style={{ 
                    color: '#94a3b8', 
                    fontStyle: 'italic', 
                    margin: 0,
                    padding: '20px',
                    textAlign: 'center',
                    background: '#f8fafc',
                    borderRadius: '12px',
                    border: '2px dashed #cbd5e1'
                  }}>
                    No documents submitted
                  </p>
                )}
              </div>

              {selectedCoach.status === 'pending' && (
                <div style={{ 
                  display: 'flex', 
                  gap: '16px', 
                  paddingTop: '24px',
                  borderTop: '3px solid #f1f5f9'
                }}>
                  <button
                    onClick={() => handleRejectCoach(selectedCoach.id)}
                    disabled={isProcessing}
                    style={{
                      flex: 1,
                      padding: '16px 28px',
                      background: 'white',
                      color: '#dc2626',
                      border: '3px solid #dc2626',
                      borderRadius: '16px',
                      fontSize: '15px',
                      fontWeight: '700',
                      cursor: isProcessing ? 'not-allowed' : 'pointer',
                      transition: 'all 0.3s ease',
                      opacity: isProcessing ? 0.5 : 1,
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      boxShadow: '0 4px 12px rgba(220, 38, 38, 0.2)'
                    }}
                    onMouseEnter={(e) => {
                      if (!isProcessing) {
                        e.target.style.background = '#dc2626';
                        e.target.style.color = 'white';
                        e.target.style.transform = 'translateY(-2px)';
                        e.target.style.boxShadow = '0 8px 20px rgba(220, 38, 38, 0.3)';
                      }
                    }}
                    onMouseLeave={(e) => {
                      if (!isProcessing) {
                        e.target.style.background = 'white';
                        e.target.style.color = '#dc2626';
                        e.target.style.transform = 'translateY(0)';
                        e.target.style.boxShadow = '0 4px 12px rgba(220, 38, 38, 0.2)';
                      }
                    }}
                  >
                    {isProcessing ? ' Processing...' : '✕ Reject & Email'}
                  </button>
                  <button
                    onClick={() => handleApproveCoach(selectedCoach.id)}
                    disabled={isProcessing}
                    style={{
                      flex: 1,
                      padding: '16px 28px',
                      background: 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
                      color: 'white',
                      border: 'none',
                      borderRadius: '16px',
                      fontSize: '15px',
                      fontWeight: '700',
                      cursor: isProcessing ? 'not-allowed' : 'pointer',
                      transition: 'all 0.3s ease',
                      opacity: isProcessing ? 0.5 : 1,
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      boxShadow: '0 8px 20px rgba(16, 185, 129, 0.3)'
                    }}
                    onMouseEnter={(e) => {
                      if (!isProcessing) {
                        e.target.style.transform = 'translateY(-2px)';
                        e.target.style.boxShadow = '0 12px 28px rgba(16, 185, 129, 0.4)';
                      }
                    }}
                    onMouseLeave={(e) => {
                      if (!isProcessing) {
                        e.target.style.transform = 'translateY(0)';
                        e.target.style.boxShadow = '0 8px 20px rgba(16, 185, 129, 0.3)';
                      }
                    }}
                  >
                    {isProcessing ? ' Processing...' : '✓ Approve & Email'}
                  </button>
                </div>
              )}

              {selectedCoach.status === 'approved' && selectedCoach.approvedAt && (
                <div style={{
                  padding: '20px',
                  background: 'linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%)',
                  borderRadius: '16px',
                  border: '3px solid #6ee7b7',
                  boxShadow: '0 4px 16px rgba(16, 185, 129, 0.2)'
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div style={{
                      width: '40px',
                      height: '40px',
                      background: '#10b981',
                      borderRadius: '12px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: '20px',
                      flexShrink: 0
                    }}>✓</div>
                    <div>
                      <p style={{ margin: '0 0 4px 0', fontSize: '15px', color: '#065f46', fontWeight: '700' }}>
                        Coach Approved
                      </p>
                      <p style={{ margin: 0, fontSize: '13px', color: '#047857', fontWeight: '600' }}>
                        Approved on {formatDate(selectedCoach.approvedAt)}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {selectedCoach.status === 'rejected' && (
                <div style={{
                  padding: '20px',
                  background: 'linear-gradient(135deg, #fee2e2 0%, #fecaca 100%)',
                  borderRadius: '16px',
                  border: '3px solid #fca5a5',
                  boxShadow: '0 4px 16px rgba(239, 68, 68, 0.2)'
                }}>
                  <div style={{ display: 'flex', alignItems: 'start', gap: '12px' }}>
                    <div style={{
                      width: '40px',
                      height: '40px',
                      background: '#ef4444',
                      borderRadius: '12px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: '20px',
                      flexShrink: 0
                    }}>✕</div>
                    <div>
                      <p style={{ margin: '0 0 6px 0', fontSize: '15px', color: '#991b1b', fontWeight: '700' }}>
                        Application Rejected
                      </p>
                      {selectedCoach.rejectionReason && (
                        <p style={{ margin: '0 0 6px 0', fontSize: '13px', color: '#7f1d1d', fontWeight: '600' }}>
                          Reason: {selectedCoach.rejectionReason}
                        </p>
                      )}
                      {selectedCoach.rejectedAt && (
                        <p style={{ margin: 0, fontSize: '12px', color: '#991b1b', fontWeight: '600' }}>
                          Rejected on {formatDate(selectedCoach.rejectedAt)}
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default CoachApprovalPage;
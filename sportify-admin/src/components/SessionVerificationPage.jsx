import React, { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, doc, updateDoc, serverTimestamp, addDoc } from 'firebase/firestore';
import { db } from '../firebase';

const SessionVerificationPage = () => {
  const [sessions, setSessions] = useState([]);
  const [selectedSession, setSelectedSession] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [filter, setFilter] = useState('awaiting_verification');
  const [verificationNotes, setVerificationNotes] = useState('');

  useEffect(() => {
    let q;
    if (filter === 'all') {
      q = query(
        collection(db, 'coach_appointments'),
        where('status', 'in', ['awaiting_verification', 'verified', 'completed'])
      );
    } else {
      q = query(
        collection(db, 'coach_appointments'),
        where('status', '==', filter)
      );
    }

    const unsubscribe = onSnapshot(q, (querySnapshot) => {
      const sessionsData = [];
      querySnapshot.forEach((doc) => {
        const data = doc.data();
        if (data.proofPhotoBase64) {
          sessionsData.push({ id: doc.id, ...data });
        }
      });

      sessionsData.sort((a, b) => {
        if (a.proofUploadedAt && b.proofUploadedAt) {
          return b.proofUploadedAt.toDate() - a.proofUploadedAt.toDate();
        }
        return 0;
      });

      setSessions(sessionsData);
      setIsLoading(false);
    });

    return () => unsubscribe();
  }, [filter]);

  const handleVerifySession = async (session, approved) => {
    if (!approved && !verificationNotes.trim()) {
      alert('Please provide a reason for rejection');
      return;
    }

    setIsProcessing(true);
    try {
      if (approved) {
        await updateDoc(doc(db, 'coach_appointments', session.id), {
          verificationStatus: 'verified',
          verifiedAt: serverTimestamp(),
          verifiedBy: 'admin',
          verificationNotes: verificationNotes.trim() || 'Session verified and approved',
          status: 'verified',
          updatedAt: serverTimestamp(),
        });

        await addDoc(collection(db, 'notifications'), {
          userId: session.coachId,
          type: 'payment',
          title: ' Training Proof Approved!',
          message: `Your training proof for the session with ${session.studentName} on ${session.date} has been verified and approved. Payment will be released soon!`,
          data: {
            appointmentId: session.id,
            action: 'view_booking',
            status: 'verified',
            amount: session.paymentAmount || session.price,
          },
          createdAt: serverTimestamp(),
          isRead: false,
          priority: 'high',
        });

        alert(` Session verified! You can now release payment of RM ${session.paymentAmount || session.price} to ${session.coachName}.`);
      } else {
        await updateDoc(doc(db, 'coach_appointments', session.id), {
          verificationStatus: 'rejected',
          verifiedAt: serverTimestamp(),
          verifiedBy: 'admin',
          verificationNotes: verificationNotes.trim(),
          status: 'confirmed',
          proofPhotoBase64: null,
          proofUploadedAt: null,
          proofNotes: null,
          updatedAt: serverTimestamp(),
        });

        await addDoc(collection(db, 'notifications'), {
          userId: session.coachId,
          type: 'system',
          title: ' Training Proof Rejected',
          message: `Your training proof for the session with ${session.studentName} on ${session.date} was not approved. Reason: ${verificationNotes.trim()}. Please upload a new proof photo.`,
          data: {
            appointmentId: session.id,
            action: 'upload_proof',
            status: 'rejected',
            rejectionReason: verificationNotes.trim(),
          },
          createdAt: serverTimestamp(),
          isRead: false,
          priority: 'high',
        });

        alert(' Session rejected. Coach will be notified to upload a new proof photo.');
      }

      setSelectedSession(null);
      setVerificationNotes('');
    } catch (error) {
      console.error('Error verifying session:', error);
      alert('Error verifying session. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleReleasePayment = async (session) => {
    const amount = session.paymentAmount || session.price;
    const confirmed = window.confirm(
      ` Release payment of RM ${amount} to ${session.coachName}?\n\nThis action cannot be undone.`
    );
    
    if (!confirmed) return;

    setIsProcessing(true);
    try {
      const platformFeePercentage = 0.10;
      const platformFee = amount * platformFeePercentage;
      const coachEarnings = amount - platformFee;

      await updateDoc(doc(db, 'coach_appointments', session.id), {
        status: 'completed',
        paymentReleasedToCoach: true,
        paymentReleasedAt: serverTimestamp(),
        coachEarnings: coachEarnings,
        platformFee: platformFee,
        updatedAt: serverTimestamp(),
      });

      await addDoc(collection(db, 'notifications'), {
        userId: session.coachId,
        type: 'payment',
        title: ' Payment Released!',
        message: `Payment for your session with ${session.studentName} on ${session.date} has been released. Amount: RM ${coachEarnings.toFixed(2)}`,
        data: {
          appointmentId: session.id,
          action: 'view_booking',
          status: 'completed',
          amount: coachEarnings,
        },
        createdAt: serverTimestamp(),
        isRead: false,
        priority: 'high',
      });

      alert(` Payment released!\n\nCoach earnings: RM ${coachEarnings.toFixed(2)}\nPlatform fee: RM ${platformFee.toFixed(2)}`);
      setSelectedSession(null);
    } catch (error) {
      console.error('Error releasing payment:', error);
      alert(' Error releasing payment. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const formatDate = (timestamp) => {
    if (!timestamp) return 'N/A';
    try {
      return timestamp.toDate().toLocaleDateString('en-MY', {
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
      case 'awaiting_verification': return '#f59e0b';
      case 'verified': return '#10b981';
      case 'completed': return '#3b82f6';
      case 'verification_rejected': return '#ef4444';
      default: return '#6b7280';
    }
  };

  const getStatusText = (status) => {
    switch (status) {
      case 'awaiting_verification': return 'Awaiting Verification';
      case 'verified': return 'Verified - Ready for Payment';
      case 'completed': return 'Completed & Paid';
      case 'verification_rejected': return 'Rejected';
      default: return status;
    }
  };

  if (isLoading) {
    return (
      <div style={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #f8fafc 0%, #fef3e2 50%, #f8fafc 100%)',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
      }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{
            width: '56px',
            height: '56px',
            border: '4px solid #fed7aa',
            borderTop: '4px solid #f59e0b',
            borderRadius: '50%',
            animation: 'spin 0.8s linear infinite',
            margin: '0 auto 20px'
          }} />
          <p style={{ color: '#64748b', fontSize: '16px', fontWeight: '600' }}>Loading sessions...</p>
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
      background: 'linear-gradient(135deg, #f8fafc 0%, #fef3e2 50%, #f8fafc 100%)',
      minHeight: '100vh'
    }}>
      <div style={{ marginBottom: '32px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '12px' }}>
          <div style={{
            width: '56px',
            height: '56px',
            background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
            borderRadius: '16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            boxShadow: '0 10px 30px rgba(245, 158, 11, 0.3)'
          }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="white">
              <path d="M21 6h-2v9H6v2c0 .55.45 1 1 1h11l4 4V7c0-.55-.45-1-1-1zm-4 6V3c0-.55-.45-1-1-1H3c-.55 0-1 .45-1 1v14l4-4h10c.55 0 1-.45 1-1z"/>
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
               Session Verification & Payments
            </h1>
            <p style={{ color: '#64748b', margin: 0, fontSize: '15px', fontWeight: '500' }}>
              Review training proofs and release payments to coaches
            </p>
          </div>
        </div>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
        gap: '20px',
        marginBottom: '32px'
      }}>
        {[
          { key: 'awaiting_verification', label: 'Awaiting Verification', count: sessions.filter(s => s.status === 'awaiting_verification').length, gradient: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)', icon: '⏳' },
          { key: 'verified', label: 'Verified (Ready)', count: sessions.filter(s => s.status === 'verified').length, gradient: 'linear-gradient(135deg, #10b981 0%, #059669 100%)', icon: '✅' },
          { key: 'completed', label: 'Paid', count: sessions.filter(s => s.status === 'completed' && s.paymentReleasedToCoach === true).length, gradient: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)', icon: '💰' },
          { key: 'verification_rejected', label: 'Rejected', count: sessions.filter(s => s.status === 'verification_rejected').length, gradient: 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)', icon: '❌' },
          { key: 'all', label: 'All', count: sessions.length, gradient: 'linear-gradient(135deg, #6b7280 0%, #4b5563 100%)', icon: '📊' }
        ].map(({ key, label, count, gradient, icon }) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            style={{
              position: 'relative',
              padding: '20px',
              background: 'white',
              borderRadius: '20px',
              border: filter === key ? '3px solid #f59e0b' : '3px solid transparent',
              cursor: 'pointer',
              transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
              boxShadow: filter === key 
                ? '0 20px 40px rgba(245, 158, 11, 0.15)' 
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
                  fontSize: '11px', 
                  fontWeight: '700', 
                  color: '#64748b', 
                  textTransform: 'uppercase', 
                  letterSpacing: '1px' 
                }}>
                  {label}
                </p>
                <p style={{ 
                  margin: 0, 
                  fontSize: '32px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  lineHeight: '1'
                }}>
                  {count}
                </p>
              </div>
              <div style={{
                width: '52px',
                height: '52px',
                background: gradient,
                borderRadius: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '22px',
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
                background: 'linear-gradient(90deg, #f59e0b, #d97706)',
                borderRadius: '0 0 17px 17px'
              }} />
            )}
          </button>
        ))}
      </div>

      <div style={{ display: 'flex', gap: '24px' }}>
        <div style={{ flex: '1', maxWidth: selectedSession ? '420px' : '100%' }}>
          {sessions.length === 0 ? (
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
                No sessions found
              </h3>
              <p style={{ color: '#94a3b8', margin: 0, fontSize: '15px' }}>
                {filter === 'awaiting_verification' 
                  ? 'Completed sessions will appear here for verification'
                  : `No ${filter.replace('_', ' ')} sessions found`
                }
              </p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {sessions.map((session) => (
                <div
                  key={session.id}
                  onClick={() => setSelectedSession(session)}
                  style={{
                    padding: '20px',
                    background: 'white',
                    borderRadius: '20px',
                    cursor: 'pointer',
                    boxShadow: selectedSession?.id === session.id 
                      ? '0 12px 32px rgba(245, 158, 11, 0.2)' 
                      : '0 4px 12px rgba(0, 0, 0, 0.06)',
                    border: selectedSession?.id === session.id ? '3px solid #f59e0b' : '3px solid transparent',
                    transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
                    transform: selectedSession?.id === session.id ? 'translateY(-2px)' : 'translateY(0)'
                  }}
                  onMouseEnter={(e) => {
                    if (selectedSession?.id !== session.id) {
                      e.currentTarget.style.boxShadow = '0 8px 20px rgba(0, 0, 0, 0.1)';
                      e.currentTarget.style.borderColor = '#fed7aa';
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (selectedSession?.id !== session.id) {
                      e.currentTarget.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.06)';
                      e.currentTarget.style.borderColor = 'transparent';
                    }
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start', marginBottom: '12px' }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <h3 style={{ 
                        margin: '0 0 8px 0', 
                        fontSize: '17px', 
                        fontWeight: '700',
                        color: '#0f172a',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap'
                      }}>
                        {session.coachName} → {session.studentName}
                      </h3>
                      <p style={{ 
                        margin: '0 0 6px 0', 
                        fontSize: '14px', 
                        color: '#64748b',
                        fontWeight: '500'
                      }}>
                         {session.date} •  {session.timeSlot} - {session.endTime}
                      </p>
                      <p style={{ 
                        margin: 0, 
                        fontSize: '16px', 
                        fontWeight: '800',
                        color: '#f59e0b'
                      }}>
                         RM {session.paymentAmount || session.price}
                      </p>
                    </div>
                    <div style={{
                      padding: '6px 14px',
                      borderRadius: '10px',
                      background: session.status === 'awaiting_verification' ? '#fef3e2' : 
                                 session.status === 'verified' ? '#d1fae5' :
                                 session.status === 'completed' ? '#dbeafe' : '#fee2e2',
                      color: session.status === 'awaiting_verification' ? '#d97706' : 
                             session.status === 'verified' ? '#059669' :
                             session.status === 'completed' ? '#2563eb' : '#dc2626',
                      fontSize: '11px',
                      fontWeight: '700',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      whiteSpace: 'nowrap',
                      flexShrink: 0,
                      marginLeft: '12px'
                    }}>
                      {getStatusText(session.status).split(' - ')[0]}
                    </div>
                  </div>
                  {session.proofUploadedAt && (
                    <div style={{
                      padding: '8px 12px',
                      background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
                      borderRadius: '10px',
                      fontSize: '12px',
                      color: '#64748b',
                      fontWeight: '600',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px'
                    }}>
                       Proof uploaded: {formatDate(session.proofUploadedAt)}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        {selectedSession && (
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
              background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
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
              
              <div style={{ position: 'relative' }}>
                <h2 style={{ 
                  margin: '0 0 8px 0', 
                  fontSize: '28px', 
                  fontWeight: '800',
                  color: 'white',
                  letterSpacing: '-0.5px'
                }}>
                  Session Verification
                </h2>
                <p style={{ 
                  margin: 0, 
                  fontSize: '16px', 
                  color: 'rgba(255, 255, 255, 0.95)',
                  fontWeight: '600'
                }}>
                  {selectedSession.coachName} → {selectedSession.studentName}
                </p>
              </div>
            </div>

            <div style={{ padding: '32px', maxHeight: '70vh', overflowY: 'auto' }}>
              <div style={{ marginBottom: '28px' }}>
                <h3 style={{ 
                  fontSize: '14px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  margin: '0 0 16px 0',
                  textTransform: 'uppercase',
                  letterSpacing: '1px'
                }}>
                   Session Details
                </h3>
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: 'repeat(2, 1fr)', 
                  gap: '16px',
                  padding: '20px',
                  background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
                  borderRadius: '16px',
                  border: '2px solid #e2e8f0'
                }}>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Coach
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedSession.coachName}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Student
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedSession.studentName}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Date
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedSession.date}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Time
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedSession.timeSlot} - {selectedSession.endTime}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Duration
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedSession.duration} hour(s)
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Payment Amount
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '18px', color: '#f59e0b', fontWeight: '800' }}>
                      RM {selectedSession.paymentAmount || selectedSession.price}
                    </p>
                  </div>
                </div>
              </div>

              {selectedSession.proofPhotoBase64 && (
                <div style={{ marginBottom: '28px' }}>
                  <h3 style={{ 
                    fontSize: '14px', 
                    fontWeight: '800', 
                    color: '#0f172a',
                    margin: '0 0 16px 0',
                    textTransform: 'uppercase',
                    letterSpacing: '1px'
                  }}>
                     Training Proof Photo
                  </h3>
                  <div style={{
                    width: '100%',
                    borderRadius: '16px',
                    overflow: 'hidden',
                    border: '3px solid #e5e7eb',
                    boxShadow: '0 8px 24px rgba(0,0,0,0.12)',
                    cursor: 'pointer',
                    transition: 'all 0.3s ease'
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.transform = 'scale(1.02)';
                    e.currentTarget.style.boxShadow = '0 12px 32px rgba(245, 158, 11, 0.2)';
                    e.currentTarget.style.borderColor = '#f59e0b';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.transform = 'scale(1)';
                    e.currentTarget.style.boxShadow = '0 8px 24px rgba(0,0,0,0.12)';
                    e.currentTarget.style.borderColor = '#e5e7eb';
                  }}
                  onClick={() => {
                    const newWindow = window.open();
                    newWindow.document.write(`<img src="data:image/jpeg;base64,${selectedSession.proofPhotoBase64}" style="width:100%;height:auto;" />`);
                  }}>
                    <img 
                      src={`data:image/jpeg;base64,${selectedSession.proofPhotoBase64}`}
                      alt="Training Proof"
                      style={{
                        width: '100%',
                        height: 'auto',
                        objectFit: 'contain',
                        display: 'block'
                      }}
                    />
                  </div>
                  {selectedSession.proofNotes && (
                    <div style={{
                      marginTop: '12px',
                      padding: '16px',
                      background: 'linear-gradient(135deg, #fafafa 0%, #f5f5f5 100%)',
                      borderRadius: '12px',
                      border: '2px solid #e5e7eb'
                    }}>
                      <label style={{ fontSize: '12px', color: '#64748b', fontWeight: '700', display: 'block', marginBottom: '6px' }}>
                        Coach's Notes:
                      </label>
                      <p style={{ margin: 0, fontSize: '14px', color: '#475569', lineHeight: '1.6', fontWeight: '500' }}>
                        {selectedSession.proofNotes}
                      </p>
                    </div>
                  )}
                  <p style={{ 
                    marginTop: '12px', 
                    fontSize: '12px', 
                    color: '#94a3b8',
                    fontStyle: 'italic',
                    textAlign: 'center',
                    fontWeight: '600'
                  }}>
                    Click image to view full size
                  </p>
                </div>
              )}

              {selectedSession.status !== 'awaiting_verification' && (
                <div style={{
                  marginBottom: '28px',
                  padding: '20px',
                  background: selectedSession.status === 'verification_rejected' 
                    ? 'linear-gradient(135deg, #fee2e2 0%, #fecaca 100%)' 
                    : 'linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%)',
                  borderRadius: '16px',
                  border: selectedSession.status === 'verification_rejected' ? '3px solid #fca5a5' : '3px solid #6ee7b7',
                  boxShadow: selectedSession.status === 'verification_rejected'
                    ? '0 4px 16px rgba(239, 68, 68, 0.2)'
                    : '0 4px 16px rgba(16, 185, 129, 0.2)'
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div style={{
                      width: '40px',
                      height: '40px',
                      borderRadius: '12px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: '20px',
                      flexShrink: 0
                    }}>
                      {selectedSession.status === 'verification_rejected' ? '' : ''}
                    </div>
                    <div>
                      <h4 style={{ 
                        margin: '0 0 4px 0', 
                        fontSize: '15px', 
                        color: selectedSession.status === 'verification_rejected' ? '#991b1b' : '#065f46',
                        fontWeight: '700'
                      }}>
                        {selectedSession.status === 'verification_rejected' ? 'Verification Rejected' : 'Verified'}
                      </h4>
                      {selectedSession.verifiedAt && (
                        <p style={{ margin: '0 0 4px 0', fontSize: '13px', color: selectedSession.status === 'verification_rejected' ? '#7f1d1d' : '#047857', fontWeight: '600' }}>
                          Verified on: {formatDate(selectedSession.verifiedAt)}
                        </p>
                      )}
                      {selectedSession.verificationNotes && (
                        <p style={{ margin: 0, fontSize: '13px', color: selectedSession.status === 'verification_rejected' ? '#7f1d1d' : '#047857', fontWeight: '500' }}>
                          Notes: {selectedSession.verificationNotes}
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {selectedSession.paymentReleasedToCoach && (
                <div style={{
                  marginBottom: '28px',
                  padding: '20px',
                  background: 'linear-gradient(135deg, #dbeafe 0%, #bfdbfe 100%)',
                  borderRadius: '16px',
                  border: '3px solid #93c5fd',
                  boxShadow: '0 4px 16px rgba(59, 130, 246, 0.2)'
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
                    <div style={{
                      width: '40px',
                      height: '40px',
                      borderRadius: '12px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: '20px',
                      flexShrink: 0
                    }}></div>
                    <h4 style={{ 
                      margin: 0, 
                      fontSize: '15px', 
                      color: '#1e40af',
                      fontWeight: '700'
                    }}>
                      Payment Released
                    </h4>
                  </div>
                  <div style={{ paddingLeft: '52px' }}>
                    <p style={{ margin: '0 0 6px 0', fontSize: '14px', color: '#1e40af', fontWeight: '600' }}>
                      Coach Earnings: <span style={{ fontSize: '18px', fontWeight: '800' }}>RM {selectedSession.coachEarnings?.toFixed(2) || (selectedSession.paymentAmount || selectedSession.price)}</span>
                    </p>
                    {selectedSession.platformFee > 0 && (
                      <p style={{ margin: '0 0 6px 0', fontSize: '13px', color: '#1e40af', fontWeight: '600' }}>
                        Platform Fee: RM {selectedSession.platformFee.toFixed(2)}
                      </p>
                    )}
                    {selectedSession.paymentReleasedAt && (
                      <p style={{ margin: 0, fontSize: '12px', color: '#1e40af', fontWeight: '500' }}>
                        Released on: {formatDate(selectedSession.paymentReleasedAt)}
                      </p>
                    )}
                  </div>
                </div>
              )}

              {selectedSession.status === 'awaiting_verification' && (
                <div style={{ marginBottom: '28px' }}>
                  <label style={{ 
                    fontSize: '14px', 
                    fontWeight: '700', 
                    color: '#0f172a',
                    display: 'block',
                    marginBottom: '8px'
                  }}>
                    Verification Notes {verificationNotes.trim() ? '(Optional)' : '(Required for rejection)'}
                  </label>
                  <textarea
                    value={verificationNotes}
                    onChange={(e) => setVerificationNotes(e.target.value)}
                    placeholder="Add notes about this verification..."
                    style={{
                      width: '100%',
                      minHeight: '100px',
                      padding: '14px',
                      border: '2px solid #e5e7eb',
                      borderRadius: '12px',
                      fontSize: '14px',
                      fontFamily: 'inherit',
                      resize: 'vertical',
                      outline: 'none',
                      transition: 'all 0.2s ease',
                      fontWeight: '500',
                      boxSizing: 'border-box'
                    }}
                    onFocus={(e) => {
                      e.target.style.borderColor = '#f59e0b';
                      e.target.style.boxShadow = '0 0 0 3px rgba(245, 158, 11, 0.1)';
                    }}
                    onBlur={(e) => {
                      e.target.style.borderColor = '#e5e7eb';
                      e.target.style.boxShadow = 'none';
                    }}
                  />
                </div>
              )}

              {selectedSession.status === 'awaiting_verification' && (
                <div style={{ 
                  display: 'flex', 
                  gap: '16px',
                  paddingTop: '24px',
                  borderTop: '3px solid #f1f5f9'
                }}>
                  <button
                    onClick={() => handleVerifySession(selectedSession, false)}
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
                    {isProcessing ? 'Processing...' : 'Reject'}
                  </button>
                  <button
                    onClick={() => handleVerifySession(selectedSession, true)}
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
                    {isProcessing ? 'Processing...' : 'Verify & Approve'}
                  </button>
                </div>
              )}

              {selectedSession.status === 'verified' && !selectedSession.paymentReleasedToCoach && (
                <div style={{ 
                  paddingTop: '24px',
                  borderTop: '3px solid #f1f5f9'
                }}>
                  <button
                    onClick={() => handleReleasePayment(selectedSession)}
                    disabled={isProcessing}
                    style={{
                      width: '100%',
                      padding: '18px 28px',
                      background: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)',
                      color: 'white',
                      border: 'none',
                      borderRadius: '16px',
                      fontSize: '16px',
                      fontWeight: '700',
                      cursor: isProcessing ? 'not-allowed' : 'pointer',
                      transition: 'all 0.3s ease',
                      opacity: isProcessing ? 0.5 : 1,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '10px',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      boxShadow: '0 8px 24px rgba(59, 130, 246, 0.3)'
                    }}
                    onMouseEnter={(e) => {
                      if (!isProcessing) {
                        e.target.style.transform = 'translateY(-2px)';
                        e.target.style.boxShadow = '0 12px 32px rgba(59, 130, 246, 0.4)';
                      }
                    }}
                    onMouseLeave={(e) => {
                      if (!isProcessing) {
                        e.target.style.transform = 'translateY(0)';
                        e.target.style.boxShadow = '0 8px 24px rgba(59, 130, 246, 0.3)';
                      }
                    }}
                  >
                    <span style={{ fontSize: '20px' }}>💰</span>
                    {isProcessing ? 'Processing...' : `Release Payment (RM ${selectedSession.paymentAmount || selectedSession.price})`}
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default SessionVerificationPage;
import React, { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, doc, updateDoc, setDoc, getDoc, writeBatch } from 'firebase/firestore';
import { db } from '../firebase';
import EmailService from '../services/EmailService';

const VenueApprovalPage = () => {
  const [pendingVenues, setPendingVenues] = useState([]);
  const [selectedVenue, setSelectedVenue] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [filter, setFilter] = useState('pending');
  const [emailStatus, setEmailStatus] = useState({ show: false, message: '', type: '' });
  const [selectedImage, setSelectedImage] = useState(null);

  useEffect(() => {
    const fetchApplications = () => {
      let q;
      if (filter === 'all') {
        q = query(collection(db, 'venue_applications'));
      } else {
        q = query(collection(db, 'venue_applications'), where('status', '==', filter));
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
        
        setPendingVenues(applications);
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

  const generateRandomPassword = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let password = '';
    for (let i = 0; i < 12; i++) {
      password += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return password;
  };

  const createVenueCourts = async (venueId, courtsData) => {
    const batch = writeBatch(db);
    
    courtsData.forEach((court, index) => {
      const courtRef = doc(collection(db, 'venues', venueId, 'courts'));
      batch.set(courtRef, {
        courtNumber: index + 1,
        courtName: court.courtName, 
        type: court.courtType, 
        isActive: true,
        isAvailable: true,
        pricePerHour: court.pricePerHour,
        createdAt: new Date()
      });
    });
    
    await batch.commit();
    console.log(`Created ${courtsData.length} courts for venue ${venueId}`);
  };

  const handleApproveVenue = async (applicationId) => {
    setIsProcessing(true);
    try {
      const application = pendingVenues.find(v => v.id === applicationId);
      const generatedPassword = generateRandomPassword();
      
      const venueOwnerId = `venue_owner_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      
      const venueOwnerData = {
        id: venueOwnerId,
        ownerName: application.ownerName,
        email: application.email,
        phone: application.phone,
        password: generatedPassword,
        role: 'venue_owner',
        status: 'approved',
        isActive: true,
        createdAt: new Date(),
        approvedAt: new Date(),
        venueId: null
      };

      await setDoc(doc(db, 'venue_owners', venueOwnerId), venueOwnerData);

      const minPrice = application.courts && application.courts.length > 0 
        ? Math.min(...application.courts.map(court => court.pricePerHour))
        : 0;

      const formatOperatingHours = (operatingHours) => {
        const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
        for (const day of days) {
          if (!operatingHours[day].closed && operatingHours[day].open && operatingHours[day].close) {
            const openTime = operatingHours[day].open;
            const closeTime = operatingHours[day].close;
            return `${openTime}-${closeTime}`;
          }
        }
        return '6AM-11PM';
      };

      const venueData = {
        id: `venue_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        name: application.venueName,
        description: application.venueDescription,
        location: `${application.venueAddress}, ${application.venueCity}, ${application.venueState} ${application.venuePostalCode}`,
        city: application.venueCity,
        state: application.venueState,
        address: application.venueAddress,
        postalCode: application.venuePostalCode,
        sports: application.sportsOffered,
        amenities: application.amenities,
        operatingHours: application.operatingHours,
        openingHours: formatOperatingHours(application.operatingHours),
        pricePerHour: minPrice, 
        totalCourts: application.courts.length,
        courts: application.courts,
        imageUrl: application.venuePhotos.length > 0 ? application.venuePhotos[0].data : null,
        photos: application.venuePhotos,
        rating: 0,
        totalReviews: 0,
        isActive: true,
        ownerId: venueOwnerId,
        ownerName: application.ownerName,
        ownerEmail: application.email,
        ownerPhone: application.phone,
        createdAt: new Date(),
        updatedAt: new Date(),
        status: 'active'
      };

      await setDoc(doc(db, 'venues', venueData.id), venueData);
      await createVenueCourts(venueData.id, application.courts);

      await updateDoc(doc(db, 'venue_owners', venueOwnerId), {
        venueId: venueData.id,
        updatedAt: new Date()
      });

      await updateDoc(doc(db, 'venue_applications', applicationId), {
        status: 'approved',
        approvedAt: new Date(),
        updatedAt: new Date(),
        venueOwnerId: venueOwnerId,
        venueId: venueData.id,
        generatedPassword: generatedPassword
      });

      const emailResult = await EmailService.sendApprovalEmail(application, generatedPassword);
      
      if (emailResult.success) {
        showEmailStatus(' Venue approved and email notification sent successfully!', 'success');
        alert(`Venue approved successfully!\n\nApproval email has been sent to: ${application.email}`);
      } else {
        showEmailStatus(' Venue approved but email notification failed to send.', 'warning');
        alert(`Venue approved successfully!\n\nHowever, the email notification failed to send. Please manually contact the venue owner.\n\nLogin Credentials:\nEmail: ${application.email}\nPassword: ${generatedPassword}`);
      }
      
      setSelectedVenue(null);
    } catch (error) {
      console.error('Error approving venue:', error);
      showEmailStatus(' Error approving venue. Please try again.', 'error');
      alert('Error approving venue. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleRejectVenue = async (applicationId, reason = '') => {
    const rejectionReason = reason || prompt('Please provide a reason for rejection (optional):') || 'Application did not meet requirements';
    const confirmReject = window.confirm(`Are you sure you want to reject this venue application?\n\nReason: ${rejectionReason}`);
    if (!confirmReject) return;

    setIsProcessing(true);
    try {
      const application = pendingVenues.find(v => v.id === applicationId);
      
      await updateDoc(doc(db, 'venue_applications', applicationId), {
        status: 'rejected',
        rejectedAt: new Date(),
        rejectionReason: rejectionReason,
        updatedAt: new Date()
      });

      const emailResult = await EmailService.sendRejectionEmail(application, rejectionReason);
      
      if (emailResult.success) {
        showEmailStatus(' Venue rejected and email notification sent successfully!', 'success');
        alert('Venue application rejected and notification email sent.');
      } else {
        showEmailStatus(' Venue rejected but email notification failed to send.', 'warning');
        alert('Venue application rejected, but the email notification failed to send. Please manually contact the venue owner.');
      }

      setSelectedVenue(null);
    } catch (error) {
      console.error('Error rejecting venue:', error);
      showEmailStatus(' Error rejecting venue. Please try again.', 'error');
      alert('Error rejecting venue. Please try again.');
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

  const renderDocumentPreview = (base64String, fileName, alt = 'Document') => {
    if (!base64String) return null;
    
    try {
      const isPDF = base64String.includes('data:application/pdf') || 
                    fileName?.toLowerCase().endsWith('.pdf');
      
      if (isPDF) {
        const handleViewPDF = () => {
          const pdfWindow = window.open('', '_blank');
          if (pdfWindow) {
            pdfWindow.document.write(`
              <!DOCTYPE html>
              <html>
                <head>
                  <title>${fileName || 'PDF Document'}</title>
                  <style>
                    body { margin: 0; padding: 0; }
                    iframe { width: 100vw; height: 100vh; border: none; }
                  </style>
                </head>
                <body>
                  <iframe src="${base64String}" type="application/pdf"></iframe>
                </body>
              </html>
            `);
            pdfWindow.document.close();
          }
        };

        return (
          <div style={{
            padding: '20px',
            backgroundColor: '#f3f4f6',
            borderRadius: '8px',
            border: '1px solid #e5e7eb',
            textAlign: 'center'
          }}>
            <div style={{ fontSize: '48px', marginBottom: '12px' }}></div>
            <p style={{ margin: '0 0 12px 0', color: '#6b7280', fontSize: '14px' }}>
              {fileName || 'PDF Document'}
            </p>
            <button
              onClick={handleViewPDF}
              style={{
                display: 'inline-block',
                padding: '8px 16px',
                backgroundColor: '#3b82f6',
                color: 'white',
                borderRadius: '6px',
                border: 'none',
                fontSize: '14px',
                fontWeight: '500',
                marginRight: '8px',
                cursor: 'pointer'
              }}
            >
              View PDF
            </button>
            <a
              href={base64String}
              download={fileName || 'document.pdf'}
              style={{
                display: 'inline-block',
                padding: '8px 16px',
                backgroundColor: '#10b981',
                color: 'white',
                borderRadius: '6px',
                textDecoration: 'none',
                fontSize: '14px',
                fontWeight: '500'
              }}
            >
              Download
            </a>
          </div>
        );
      }
      
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
            border: '1px solid #e5e7eb',
            cursor: 'pointer'
          }}
          onClick={() => setSelectedImage(imageSrc)}
          onError={(e) => {
            e.target.style.display = 'none';
          }}
        />
      );
    } catch (error) {
      return <div style={{ color: '#ef4444' }}>Error loading document</div>;
    }
  };

  const ImageModal = ({ imageUrl, onClose }) => {
    if (!imageUrl) return null;
    
    return (
      <div 
        onClick={onClose}
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0, 0, 0, 0.9)',
          zIndex: 9999,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '20px',
          animation: 'fadeIn 0.3s ease'
        }}
      >
        <button
          onClick={onClose}
          style={{
            position: 'absolute',
            top: '20px',
            right: '20px',
            backgroundColor: 'white',
            border: 'none',
            borderRadius: '50%',
            width: '40px',
            height: '40px',
            fontSize: '24px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontWeight: 'bold',
            boxShadow: '0 4px 12px rgba(0,0,0,0.3)'
          }}
        >
          ×
        </button>
        <img
          src={imageUrl}
          alt="Full size"
          style={{
            maxWidth: '90%',
            maxHeight: '90%',
            objectFit: 'contain',
            borderRadius: '8px'
          }}
          onClick={(e) => e.stopPropagation()}
        />
        <style>{`
          @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
          }
        `}</style>
      </div>
    );
  };

  if (isLoading) {
    return (
      <div style={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #f8fafc 0%, #f0fdf4 50%, #f8fafc 100%)',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
      }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{
            width: '56px',
            height: '56px',
            border: '4px solid #d1fae5',
            borderTop: '4px solid #10b981',
            borderRadius: '50%',
            animation: 'spin 0.8s linear infinite',
            margin: '0 auto 20px'
          }} />
          <p style={{ color: '#64748b', fontSize: '16px', fontWeight: '600' }}>Loading venue applications...</p>
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
      background: 'linear-gradient(135deg, #f8fafc 0%, #f0fdf4 50%, #f8fafc 100%)',
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
            background: 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
            borderRadius: '16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            boxShadow: '0 10px 30px rgba(16, 185, 129, 0.3)'
          }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="white">
              <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V7.3l7-3.11v8.8z"/>
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
              Venue Applications
            </h1>
            <p style={{ color: '#64748b', margin: 0, fontSize: '15px', fontWeight: '500' }}>
              Review and approve venue owner registrations
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
          { key: 'pending', label: 'Pending', count: pendingVenues.filter(v => v.status === 'pending').length, gradient: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)', icon: '⏳' },
          { key: 'approved', label: 'Approved', count: pendingVenues.filter(v => v.status === 'approved').length, gradient: 'linear-gradient(135deg, #10b981 0%, #059669 100%)', icon: '✓' },
          { key: 'rejected', label: 'Rejected', count: pendingVenues.filter(v => v.status === 'rejected').length, gradient: 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)', icon: '✕' },
          { key: 'all', label: 'Total', count: pendingVenues.length, gradient: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)', icon: '🏟️' }
        ].map(({ key, label, count, gradient, icon }) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            style={{
              position: 'relative',
              padding: '24px',
              background: 'white',
              borderRadius: '20px',
              border: filter === key ? '3px solid #10b981' : '3px solid transparent',
              cursor: 'pointer',
              transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
              boxShadow: filter === key 
                ? '0 20px 40px rgba(16, 185, 129, 0.15)' 
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
                background: 'linear-gradient(90deg, #10b981, #059669)',
                borderRadius: '0 0 17px 17px'
              }} />
            )}
          </button>
        ))}
      </div>

      <div style={{ display: 'flex', gap: '24px' }}>
        <div style={{ flex: '1', maxWidth: selectedVenue ? '420px' : '100%' }}>
          {pendingVenues.length === 0 ? (
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
                  ? 'New venue applications will appear here'
                  : `No ${filter} venue applications found`
                }
              </p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {pendingVenues.map((venue) => (
                <div
                  key={venue.id}
                  onClick={() => setSelectedVenue(venue)}
                  style={{
                    padding: '20px',
                    background: 'white',
                    borderRadius: '20px',
                    cursor: 'pointer',
                    boxShadow: selectedVenue?.id === venue.id 
                      ? '0 12px 32px rgba(16, 185, 129, 0.2)' 
                      : '0 4px 12px rgba(0, 0, 0, 0.06)',
                    border: selectedVenue?.id === venue.id ? '3px solid #10b981' : '3px solid transparent',
                    transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
                    transform: selectedVenue?.id === venue.id ? 'translateY(-2px)' : 'translateY(0)'
                  }}
                  onMouseEnter={(e) => {
                    if (selectedVenue?.id !== venue.id) {
                      e.currentTarget.style.boxShadow = '0 8px 20px rgba(0, 0, 0, 0.1)';
                      e.currentTarget.style.borderColor = '#d1fae5';
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (selectedVenue?.id !== venue.id) {
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
                      {venue.venuePhotos && venue.venuePhotos.length > 0 ? (
                        <img 
                          src={venue.venuePhotos[0].data}
                          alt="Venue"
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
                        }}></div>
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
                        {venue.status === 'pending' ? '' : venue.status === 'approved' ? '✓' : '✕'}
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
                        {venue.venueName}
                      </h3>
                      <p style={{ 
                        margin: '0 0 6px 0', 
                        fontSize: '14px', 
                        color: '#64748b',
                        fontWeight: '500'
                      }}>
                         {venue.ownerName} •  {venue.venueCity}, {venue.venueState}
                      </p>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                        <span style={{
                          padding: '4px 12px',
                          borderRadius: '8px',
                          background: venue.status === 'pending' ? '#fef3e2' : 
                                     venue.status === 'approved' ? '#d1fae5' : '#fee2e2',
                          color: venue.status === 'pending' ? '#d97706' : 
                                 venue.status === 'approved' ? '#059669' : '#dc2626',
                          fontSize: '11px',
                          fontWeight: '700',
                          textTransform: 'uppercase',
                          letterSpacing: '0.5px'
                        }}>
                          {venue.status}
                        </span>
                        <span style={{ 
                          fontSize: '12px', 
                          color: '#94a3b8',
                          fontWeight: '500'
                        }}>
                          {formatDate(venue.createdAt)}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {selectedVenue && (
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
              background: 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
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
                  {selectedVenue.venuePhotos && selectedVenue.venuePhotos.length > 0 ? (
                    <img 
                      src={selectedVenue.venuePhotos[0].data}
                      alt="Venue"
                      style={{
                        width: '100%',
                        height: '100%',
                        objectFit: 'cover'
                      }}
                    />
                  ) : (
                    <div style={{ fontSize: '48px', color: 'white' }}></div>
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
                    {selectedVenue.venueName}
                  </h2>
                  <p style={{ 
                    margin: '0 0 12px 0', 
                    fontSize: '16px', 
                    color: 'rgba(255, 255, 255, 0.95)',
                    fontWeight: '600'
                  }}>
                    Owner: {selectedVenue.ownerName}
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
                    {selectedVenue.status}
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
                   Owner Information
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
                      Name
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedVenue.ownerName}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Email
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedVenue.email}
                    </p>
                  </div>
                  <div>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Phone
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600' }}>
                      {selectedVenue.phone}
                    </p>
                  </div>
                </div>
              </div>

              <div style={{ marginBottom: '28px' }}>
                <h3 style={{ 
                  fontSize: '14px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  margin: '0 0 16px 0',
                  textTransform: 'uppercase',
                  letterSpacing: '1px'
                }}>
                   Venue Details
                </h3>
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', 
                  gap: '16px',
                  marginBottom: '16px'
                }}>
                  <div style={{
                    padding: '16px',
                    background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
                    borderRadius: '12px',
                    border: '2px solid #e2e8f0'
                  }}>
                    <label style={{ fontSize: '11px', color: '#64748b', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Address
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '14px', color: '#0f172a', fontWeight: '600', lineHeight: '1.5' }}>
                      {selectedVenue.venueAddress}, {selectedVenue.venueCity}, {selectedVenue.venueState} {selectedVenue.venuePostalCode}
                    </p>
                  </div>
                  <div style={{
                    padding: '16px',
                    background: 'linear-gradient(135deg, #fef3e2 0%, #fed7aa 100%)',
                    borderRadius: '12px',
                    border: '2px solid #fde68a'
                  }}>
                    <label style={{ fontSize: '11px', color: '#92400e', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Total Courts
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '24px', color: '#d97706', fontWeight: '800' }}>
                      {selectedVenue.totalCourts}
                    </p>
                  </div>
                  <div style={{
                    padding: '16px',
                    background: 'linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%)',
                    borderRadius: '12px',
                    border: '2px solid #6ee7b7'
                  }}>
                    <label style={{ fontSize: '11px', color: '#065f46', fontWeight: '700', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      Price per Hour
                    </label>
                    <p style={{ margin: '6px 0 0 0', fontSize: '24px', color: '#10b981', fontWeight: '800' }}>
                      RM {selectedVenue.pricePerHour}
                    </p>
                  </div>
                </div>

                <div style={{ marginBottom: '16px' }}>
                  <label style={{ fontSize: '12px', color: '#64748b', fontWeight: '700', display: 'block', marginBottom: '8px' }}>
                    Description
                  </label>
                  <p style={{ 
                    margin: 0, 
                    fontSize: '15px', 
                    color: '#475569',
                    lineHeight: '1.7',
                    background: 'linear-gradient(135deg, #fafafa 0%, #f5f5f5 100%)',
                    padding: '16px',
                    borderRadius: '12px',
                    border: '2px solid #e5e7eb',
                    fontWeight: '500'
                  }}>
                    {selectedVenue.venueDescription}
                  </p>
                </div>

                {selectedVenue.sportsOffered && selectedVenue.sportsOffered.length > 0 && (
                  <div style={{ marginBottom: '16px' }}>
                    <label style={{ fontSize: '12px', color: '#64748b', fontWeight: '700', display: 'block', marginBottom: '8px' }}>
                      Sports Offered
                    </label>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
                      {selectedVenue.sportsOffered.map((sport, index) => (
                        <span
                          key={index}
                          style={{
                            padding: '8px 16px',
                            background: 'linear-gradient(135deg, #e0f2fe 0%, #bae6fd 100%)',
                            color: '#0369a1',
                            borderRadius: '10px',
                            fontSize: '13px',
                            fontWeight: '700',
                            border: '2px solid #7dd3fc'
                          }}
                        >
                          {sport}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {selectedVenue.amenities && selectedVenue.amenities.length > 0 && (
                  <div>
                    <label style={{ fontSize: '12px', color: '#64748b', fontWeight: '700', display: 'block', marginBottom: '8px' }}>
                      Amenities
                    </label>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
                      {selectedVenue.amenities.map((amenity, index) => (
                        <span
                          key={index}
                          style={{
                            padding: '8px 16px',
                            background: 'linear-gradient(135deg, #f3e8ff 0%, #e9d5ff 100%)',
                            color: '#7e22ce',
                            borderRadius: '10px',
                            fontSize: '13px',
                            fontWeight: '700',
                            border: '2px solid #c084fc'
                          }}
                        >
                          {amenity}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              <div style={{ marginBottom: '28px' }}>
                <h3 style={{ 
                  fontSize: '14px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  margin: '0 0 16px 0',
                  textTransform: 'uppercase',
                  letterSpacing: '1px'
                }}>
                   Documents
                </h3>
                
                {selectedVenue.businessLicenseBase64 && (
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
                       Business License
                      {selectedVenue.businessLicenseFileName && (
                        <span style={{ fontWeight: '400', color: '#94a3b8', fontSize: '12px', marginLeft: '8px' }}>
                          ({selectedVenue.businessLicenseFileName})
                        </span>
                      )}
                    </h4>
                    {renderDocumentPreview(selectedVenue.businessLicenseBase64, selectedVenue.businessLicenseFileName, 'Business License')}
                  </div>
                )}

                {selectedVenue.ownershipProofBase64 && (
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
                       Ownership Proof
                      {selectedVenue.ownershipProofFileName && (
                        <span style={{ fontWeight: '400', color: '#94a3b8', fontSize: '12px', marginLeft: '8px' }}>
                          ({selectedVenue.ownershipProofFileName})
                        </span>
                      )}
                    </h4>
                    {renderDocumentPreview(selectedVenue.ownershipProofBase64, selectedVenue.ownershipProofFileName, 'Ownership Proof')}
                  </div>
                )}
              </div>

              {selectedVenue.venuePhotos && selectedVenue.venuePhotos.length > 0 && (
                <div style={{ marginBottom: '28px' }}>
                  <h3 style={{ 
                    fontSize: '14px', 
                    fontWeight: '800', 
                    color: '#0f172a',
                    margin: '0 0 16px 0',
                    textTransform: 'uppercase',
                    letterSpacing: '1px'
                  }}>
                     Venue Photos ({selectedVenue.venuePhotos.length})
                  </h3>
                  <div style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))',
                    gap: '12px'
                  }}>
                    {selectedVenue.venuePhotos.map((photo, index) => (
                      <div 
                        key={index} 
                        style={{
                          border: '3px solid #e5e7eb',
                          borderRadius: '12px',
                          overflow: 'hidden',
                          cursor: 'pointer',
                          transition: 'all 0.3s ease',
                          boxShadow: '0 2px 8px rgba(0,0,0,0.1)'
                        }}
                        onClick={() => setSelectedImage(photo.data)}
                        onMouseEnter={(e) => {
                          e.currentTarget.style.transform = 'scale(1.05)';
                          e.currentTarget.style.borderColor = '#10b981';
                          e.currentTarget.style.boxShadow = '0 8px 20px rgba(16, 185, 129, 0.3)';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.transform = 'scale(1)';
                          e.currentTarget.style.borderColor = '#e5e7eb';
                          e.currentTarget.style.boxShadow = '0 2px 8px rgba(0,0,0,0.1)';
                        }}
                      >
                        <img
                          src={photo.data}
                          alt={`Venue ${index + 1}`}
                          style={{
                            width: '100%',
                            height: '120px',
                            objectFit: 'cover'
                          }}
                        />
                        <p style={{
                          margin: 0,
                          padding: '8px',
                          fontSize: '11px',
                          backgroundColor: '#f9fafb',
                          color: '#64748b',
                          textAlign: 'center',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                          fontWeight: '600'
                        }}>
                          {photo.name}
                        </p>
                      </div>
                    ))}
                  </div>
                  <p style={{ 
                    fontSize: '12px', 
                    color: '#94a3b8', 
                    margin: '12px 0 0 0',
                    fontStyle: 'italic',
                    textAlign: 'center'
                  }}>
                     Click on any photo to view full size
                  </p>
                </div>
              )}

              {selectedVenue.additionalNotes && (
                <div style={{ marginBottom: '28px' }}>
                  <h3 style={{ 
                    fontSize: '14px', 
                    fontWeight: '800', 
                    color: '#0f172a',
                    margin: '0 0 12px 0',
                    textTransform: 'uppercase',
                    letterSpacing: '1px'
                  }}>
                     Additional Notes
                  </h3>
                  <p style={{ 
                    margin: 0, 
                    fontSize: '15px', 
                    color: '#475569',
                    lineHeight: '1.7',
                    background: 'linear-gradient(135deg, #fafafa 0%, #f5f5f5 100%)',
                    padding: '16px',
                    borderRadius: '12px',
                    border: '2px solid #e5e7eb',
                    fontWeight: '500'
                  }}>
                    {selectedVenue.additionalNotes}
                  </p>
                </div>
              )}

              {selectedVenue.status === 'pending' && (
                <div style={{ 
                  display: 'flex', 
                  gap: '16px', 
                  paddingTop: '24px',
                  borderTop: '3px solid #f1f5f9'
                }}>
                  <button
                    onClick={() => handleRejectVenue(selectedVenue.id)}
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
                    onClick={() => handleApproveVenue(selectedVenue.id)}
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

              {selectedVenue.status === 'approved' && selectedVenue.approvedAt && (
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
                         Venue Approved
                      </p>
                      <p style={{ margin: 0, fontSize: '13px', color: '#047857', fontWeight: '600' }}>
                        Approved on {formatDate(selectedVenue.approvedAt)}
                      </p>
                      {selectedVenue.venueOwnerId && (
                        <p style={{ margin: '4px 0 0 0', fontSize: '12px', color: '#047857', fontWeight: '500' }}>
                          Owner ID: {selectedVenue.venueOwnerId}
                        </p>
                      )}
                      {selectedVenue.venueId && (
                        <p style={{ margin: '4px 0 0 0', fontSize: '12px', color: '#047857', fontWeight: '500' }}>
                          Venue ID: {selectedVenue.venueId}
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {selectedVenue.status === 'rejected' && (
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
                      {selectedVenue.rejectionReason && (
                        <p style={{ margin: '0 0 6px 0', fontSize: '13px', color: '#7f1d1d', fontWeight: '600' }}>
                          Reason: {selectedVenue.rejectionReason}
                        </p>
                      )}
                      {selectedVenue.rejectedAt && (
                        <p style={{ margin: 0, fontSize: '12px', color: '#991b1b', fontWeight: '600' }}>
                          Rejected on {formatDate(selectedVenue.rejectedAt)}
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

      {selectedImage && (
        <ImageModal 
          imageUrl={selectedImage} 
          onClose={() => setSelectedImage(null)} 
        />
      )}
    </div>
  );
};

export default VenueApprovalPage;

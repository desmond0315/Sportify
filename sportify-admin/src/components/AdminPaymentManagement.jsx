import React, { useState, useEffect } from 'react';
import { collection, query, where, getDocs, updateDoc, doc, addDoc, Timestamp } from 'firebase/firestore';
import { db } from '../firebase';

const AdminPaymentManagement = () => {
  const [bookings, setBookings] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [filterStatus, setFilterStatus] = useState('all');
  const [selectedBooking, setSelectedBooking] = useState(null);
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    loadBookings();
  }, []);

  const loadBookings = async () => {
    setIsLoading(true);
    try {
      const bookingsRef = collection(db, 'bookings');
      
      // Get ALL court bookings first, then filter in JavaScript
      const q = query(
        bookingsRef,
        where('bookingType', '==', 'court')
      );

      const snapshot = await getDocs(q);
      const allBookings = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));

      // Filter for relevant payment statuses
      const bookingsData = allBookings.filter(booking => {
        const status = booking.paymentStatus?.toLowerCase();
        const bookingStatus = booking.status?.toLowerCase();
        return status === 'completed' || 
               status === 'paid' || 
               status === 'held_by_admin' || 
               status === 'released_to_venue' ||
               bookingStatus === 'refund_requested';
      });

      // Sort by creation date
      bookingsData.sort((a, b) => {
        const aTime = a.createdAt?.toMillis() || 0;
        const bTime = b.createdAt?.toMillis() || 0;
        return bTime - aTime;
      });

      setBookings(bookingsData);
    } catch (error) {
      console.error('Error loading bookings:', error);
      alert('Failed to load bookings');
    } finally {
      setIsLoading(false);
    }
  };

  const getFilteredBookings = () => {
    if (filterStatus === 'all') return bookings;
    
    if (filterStatus === 'held') {
      return bookings.filter(b => {
        const status = b.paymentStatus?.toLowerCase();
        return status === 'completed' || status === 'paid' || status === 'held_by_admin';
      });
    }
    
    if (filterStatus === 'released') {
      return bookings.filter(b => b.paymentStatus?.toLowerCase() === 'released_to_venue');
    }
    
    return bookings;
  };

  const canRefund = (booking) => {
    if (!booking.date || !booking.timeSlot) return false;
    
    try {
      const [year, month, day] = booking.date.split('-').map(Number);
      const [hour, minute] = booking.timeSlot.split(':').map(Number);
      
      const bookingDateTime = new Date(year, month - 1, day, hour, minute);
      const now = new Date();
      const hoursUntilBooking = (bookingDateTime - now) / (1000 * 60 * 60);
      
      return hoursUntilBooking >= 24;
    } catch (error) {
      console.error('Error calculating refund eligibility:', error);
      return false;
    }
  };

  const handleReleaseToVenue = async (booking) => {
    if (!window.confirm(`Release RM ${booking.totalPrice} to ${booking.venueName}?`)) {
      return;
    }

    setIsProcessing(true);
    try {
      await updateDoc(doc(db, 'bookings', booking.id), {
        paymentStatus: 'released_to_venue',
        releasedAt: Timestamp.now(),
        releasedBy: 'admin',
        updatedAt: Timestamp.now()
      });

      // Create notification for venue owner
      await addDoc(collection(db, 'notifications'), {
        userId: booking.venueOwnerId || 'venue_owner',
        type: 'payment',
        title: 'Payment Released',
        message: `RM ${booking.totalPrice} has been released for booking at ${booking.venueName} on ${booking.date}`,
        data: {
          bookingId: booking.id,
          amount: booking.totalPrice,
          action: 'view_revenue'
        },
        createdAt: Timestamp.now(),
        isRead: false,
        priority: 'high'
      });

      alert('Payment released to venue owner successfully!');
      loadBookings();
    } catch (error) {
      console.error('Error releasing payment:', error);
      alert('Failed to release payment. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleRefund = async (booking) => {
    if (!canRefund(booking)) {
      alert('Refund not allowed. Bookings can only be refunded 24 hours before the scheduled time.');
      return;
    }

    if (!window.confirm(`Refund RM ${booking.totalPrice} to ${booking.userName}? This action cannot be undone.`)) {
      return;
    }

    setIsProcessing(true);
    try {
      await updateDoc(doc(db, 'bookings', booking.id), {
        status: 'refunded',
        paymentStatus: 'refunded',
        refundedAt: Timestamp.now(),
        refundedBy: 'admin',
        updatedAt: Timestamp.now()
      });

      // Create notification for user
      await addDoc(collection(db, 'notifications'), {
        userId: booking.userId,
        type: 'payment',
        title: 'Refund Successful',
        message: `Your booking at ${booking.venueName} on ${booking.date} has been refunded. RM ${booking.totalPrice} will be returned to your account within 5-7 working days.`,
        data: {
          bookingId: booking.id,
          amount: booking.totalPrice,
          action: 'view_booking'
        },
        createdAt: Timestamp.now(),
        isRead: false,
        priority: 'high'
      });

      alert('Refund processed successfully! User has been notified.');
      loadBookings();
    } catch (error) {
      console.error('Error processing refund:', error);
      alert('Failed to process refund. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const getStatusBadge = (paymentStatus, bookingStatus) => {
    const status = paymentStatus?.toLowerCase() || '';
    const bStatus = bookingStatus?.toLowerCase() || '';
    
    // Check if refund requested
    if (bStatus === 'refund_requested') {
      return (
        <span style={{
          padding: '6px 12px',
          backgroundColor: '#fed7aa',
          color: '#c2410c',
          borderRadius: '12px',
          fontSize: '12px',
          fontWeight: '600',
          display: 'inline-flex',
          alignItems: 'center',
          gap: '4px'
        }}>
          <span style={{ fontSize: '14px' }}></span>
          Refund Requested
        </span>
      );
    }
    
    const statusConfig = {
      completed: { bg: '#fef3c7', color: '#d97706', text: 'Paid - Held by Admin' },
      paid: { bg: '#fef3c7', color: '#d97706', text: 'Paid - Held by Admin' },
      held_by_admin: { bg: '#fef3c7', color: '#d97706', text: 'Held by Admin' },
      released_to_venue: { bg: '#d1fae5', color: '#059669', text: 'Released to Venue' },
      refunded: { bg: '#fee2e2', color: '#dc2626', text: 'Refunded' }
    };

    const config = statusConfig[status] || { bg: '#f3f4f6', color: '#6b7280', text: paymentStatus };

    return (
      <span style={{
        padding: '6px 12px',
        backgroundColor: config.bg,
        color: config.color,
        borderRadius: '12px',
        fontSize: '12px',
        fontWeight: '600',
        textTransform: 'capitalize'
      }}>
        {config.text}
      </span>
    );
  };

  const formatDate = (dateString) => {
    try {
      const [year, month, day] = dateString.split('-');
      const date = new Date(year, month - 1, day);
      return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    } catch {
      return dateString;
    }
  };

  const calculateStats = () => {
    const held = bookings.filter(b => {
      const status = b.paymentStatus?.toLowerCase();
      return status === 'completed' || status === 'held_by_admin' || status === 'paid';
    });
    const released = bookings.filter(b => b.paymentStatus?.toLowerCase() === 'released_to_venue');
    const refunded = bookings.filter(b => b.paymentStatus?.toLowerCase() === 'refunded');

    return {
      heldAmount: held.reduce((sum, b) => sum + (b.totalPrice || 0), 0),
      heldCount: held.length,
      releasedAmount: released.reduce((sum, b) => sum + (b.totalPrice || 0), 0),
      releasedCount: released.length,
      refundedAmount: refunded.reduce((sum, b) => sum + (b.totalPrice || 0), 0),
      refundedCount: refunded.length
    };
  };

  const stats = calculateStats();
  const filteredBookings = getFilteredBookings();

  if (isLoading) {
    return (
      <div style={{ minHeight: '400px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{
            width: '40px',
            height: '40px',
            border: '4px solid #f3f4f6',
            borderTop: '4px solid #3b82f6',
            borderRadius: '50%',
            animation: 'spin 1s linear infinite',
            margin: '0 auto 16px'
          }} />
          <div style={{ color: '#6b7280' }}>Loading payments...</div>
        </div>
        <style>{`@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }`}</style>
      </div>
    );
  }

  return (
    <div>
      <div style={{ marginBottom: '32px' }}>
        <h1 style={{ fontSize: '28px', fontWeight: 'bold', color: '#1f2937', margin: '0 0 8px 0' }}>
          Payment Management
        </h1>
        <p style={{ fontSize: '16px', color: '#6b7280', margin: 0 }}>
          Manage escrow payments, releases, and refunds
        </p>
      </div>

      {/* Stats Cards */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))',
        gap: '16px',
        marginBottom: '32px'
      }}>
        <div style={{
          backgroundColor: 'white',
          padding: '20px',
          borderRadius: '12px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.05)',
          border: '1px solid #e5e7eb'
        }}>
          <p style={{ fontSize: '13px', color: '#6b7280', margin: '0 0 8px 0', fontWeight: '500' }}>
            Held by Admin
          </p>
          <p style={{ fontSize: '28px', fontWeight: 'bold', color: '#d97706', margin: '0 0 4px 0' }}>
            RM {stats.heldAmount.toFixed(2)}
          </p>
          <p style={{ fontSize: '12px', color: '#9ca3af', margin: 0 }}>
            {stats.heldCount} payment{stats.heldCount !== 1 ? 's' : ''}
          </p>
        </div>

        <div style={{
          backgroundColor: 'white',
          padding: '20px',
          borderRadius: '12px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.05)',
          border: '1px solid #e5e7eb'
        }}>
          <p style={{ fontSize: '13px', color: '#6b7280', margin: '0 0 8px 0', fontWeight: '500' }}>
            Released to Venues
          </p>
          <p style={{ fontSize: '28px', fontWeight: 'bold', color: '#059669', margin: '0 0 4px 0' }}>
            RM {stats.releasedAmount.toFixed(2)}
          </p>
          <p style={{ fontSize: '12px', color: '#9ca3af', margin: 0 }}>
            {stats.releasedCount} payment{stats.releasedCount !== 1 ? 's' : ''}
          </p>
        </div>

        <div style={{
          backgroundColor: 'white',
          padding: '20px',
          borderRadius: '12px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.05)',
          border: '1px solid #e5e7eb'
        }}>
          <p style={{ fontSize: '13px', color: '#6b7280', margin: '0 0 8px 0', fontWeight: '500' }}>
            Total Refunded
          </p>
          <p style={{ fontSize: '28px', fontWeight: 'bold', color: '#dc2626', margin: '0 0 4px 0' }}>
            RM {stats.refundedAmount.toFixed(2)}
          </p>
          <p style={{ fontSize: '12px', color: '#9ca3af', margin: 0 }}>
            {stats.refundedCount} refund{stats.refundedCount !== 1 ? 's' : ''}
          </p>
        </div>
      </div>

      {/* Filters */}
      <div style={{
        backgroundColor: 'white',
        padding: '20px',
        borderRadius: '12px',
        boxShadow: '0 4px 6px rgba(0,0,0,0.05)',
        border: '1px solid #e5e7eb',
        marginBottom: '24px'
      }}>
        <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          <span style={{ fontSize: '14px', fontWeight: '600', color: '#374151' }}>Filter:</span>
          <button
            onClick={() => setFilterStatus('all')}
            style={{
              padding: '8px 16px',
              backgroundColor: filterStatus === 'all' ? '#3b82f6' : 'white',
              color: filterStatus === 'all' ? 'white' : '#6b7280',
              border: `2px solid ${filterStatus === 'all' ? '#3b82f6' : '#e5e7eb'}`,
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '14px'
            }}
          >
            All Payments
          </button>
          <button
            onClick={() => setFilterStatus('held')}
            style={{
              padding: '8px 16px',
              backgroundColor: filterStatus === 'held' ? '#f59e0b' : 'white',
              color: filterStatus === 'held' ? 'white' : '#6b7280',
              border: `2px solid ${filterStatus === 'held' ? '#f59e0b' : '#e5e7eb'}`,
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '14px'
            }}
          >
            Held by Admin
          </button>
          <button
            onClick={() => setFilterStatus('released')}
            style={{
              padding: '8px 16px',
              backgroundColor: filterStatus === 'released' ? '#10b981' : 'white',
              color: filterStatus === 'released' ? 'white' : '#6b7280',
              border: `2px solid ${filterStatus === 'released' ? '#10b981' : '#e5e7eb'}`,
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '14px'
            }}
          >
            Released
          </button>
          <button
            onClick={loadBookings}
            style={{
              marginLeft: 'auto',
              padding: '8px 16px',
              backgroundColor: '#3b82f6',
              color: 'white',
              border: 'none',
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '14px'
            }}
          >
            Refresh
          </button>
        </div>
      </div>

      {/* Bookings Table */}
      {filteredBookings.length === 0 ? (
        <div style={{
          backgroundColor: 'white',
          padding: '60px 20px',
          borderRadius: '12px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.05)',
          border: '1px solid #e5e7eb',
          textAlign: 'center'
        }}>
          <div style={{ fontSize: '64px', marginBottom: '16px' }}></div>
          <h3 style={{ color: '#6b7280', margin: '0 0 8px 0' }}>No Payments Found</h3>
          <p style={{ color: '#9ca3af', margin: 0 }}>
            No payments match the selected filter
          </p>
        </div>
      ) : (
        <div style={{
          backgroundColor: 'white',
          borderRadius: '12px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.05)',
          border: '1px solid #e5e7eb',
          overflow: 'hidden'
        }}>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ backgroundColor: '#f9fafb', borderBottom: '2px solid #e5e7eb' }}>
                  <th style={{ padding: '16px', textAlign: 'left', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Booking Details
                  </th>
                  <th style={{ padding: '16px', textAlign: 'left', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Customer
                  </th>
                  <th style={{ padding: '16px', textAlign: 'left', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Venue
                  </th>
                  <th style={{ padding: '16px', textAlign: 'right', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Amount
                  </th>
                  <th style={{ padding: '16px', textAlign: 'center', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Status
                  </th>
                  <th style={{ padding: '16px', textAlign: 'center', fontSize: '13px', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody>
                {filteredBookings.map(booking => (
                  <tr key={booking.id} style={{ borderBottom: '1px solid #e5e7eb' }}>
                    <td style={{ padding: '16px' }}>
                      <div style={{ fontSize: '14px', color: '#1f2937', fontWeight: '600' }}>
                        {formatDate(booking.date)}
                      </div>
                      <div style={{ fontSize: '13px', color: '#6b7280' }}>
                        {booking.timeSlot} - {booking.endTime}
                      </div>
                      <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>
                        {booking.courtName || `Court ${booking.courtNumber}`}
                      </div>
                    </td>
                    <td style={{ padding: '16px' }}>
                      <div style={{ fontSize: '14px', color: '#1f2937', fontWeight: '500' }}>
                        {booking.userName}
                      </div>
                      <div style={{ fontSize: '12px', color: '#6b7280' }}>
                        {booking.userEmail}
                      </div>
                    </td>
                    <td style={{ padding: '16px', fontSize: '14px', color: '#1f2937' }}>
                      {booking.venueName}
                    </td>
                    <td style={{ padding: '16px', textAlign: 'right', fontSize: '16px', color: '#10b981', fontWeight: '700' }}>
                      RM {booking.totalPrice?.toFixed(2) || '0.00'}
                    </td>
                    <td style={{ padding: '16px', textAlign: 'center' }}>
                      {getStatusBadge(booking.paymentStatus, booking.status)}
                    </td>
                    <td style={{ padding: '16px', textAlign: 'center' }}>
                      <div style={{ display: 'flex', gap: '8px', justifyContent: 'center' }}>
                        {/* Show special handling for refund requests */}
                        {booking.status?.toLowerCase() === 'refund_requested' && (
                          <>
                            <button
                              onClick={() => handleRefund(booking)}
                              disabled={isProcessing}
                              style={{
                                padding: '6px 12px',
                                backgroundColor: isProcessing ? '#d1d5db' : '#f59e0b',
                                color: 'white',
                                border: 'none',
                                borderRadius: '6px',
                                cursor: isProcessing ? 'not-allowed' : 'pointer',
                                fontSize: '12px',
                                fontWeight: '600'
                              }}
                            >
                              Approve Refund
                            </button>
                            <button
                              onClick={async () => {
                                if (window.confirm('Reject this refund request?')) {
                                  try {
                                    await updateDoc(doc(db, 'bookings', booking.id), {
                                      status: 'confirmed',
                                      refundRequestRejected: true,
                                      refundRejectedAt: Timestamp.now(),
                                      updatedAt: Timestamp.now()
                                    });
                                    
                                    await addDoc(collection(db, 'notifications'), {
                                      userId: booking.userId,
                                      type: 'payment',
                                      title: 'Refund Request Rejected',
                                      message: `Your refund request for booking at ${booking.venueName} on ${booking.date} has been rejected. The booking remains active.`,
                                      data: {
                                        bookingId: booking.id,
                                        action: 'view_booking'
                                      },
                                      createdAt: Timestamp.now(),
                                      isRead: false,
                                      priority: 'high'
                                    });
                                    
                                    alert('Refund request rejected');
                                    loadBookings();
                                  } catch (error) {
                                    alert('Error rejecting refund: ' + error);
                                  }
                                }
                              }}
                              disabled={isProcessing}
                              style={{
                                padding: '6px 12px',
                                backgroundColor: isProcessing ? '#d1d5db' : '#6b7280',
                                color: 'white',
                                border: 'none',
                                borderRadius: '6px',
                                cursor: isProcessing ? 'not-allowed' : 'pointer',
                                fontSize: '12px',
                                fontWeight: '600'
                              }}
                            >
                              Reject
                            </button>
                          </>
                        )}
                        
                        {/* Regular payment actions */}
                        {booking.status?.toLowerCase() !== 'refund_requested' && (
                          <>
                            {(booking.paymentStatus?.toLowerCase() === 'completed' || 
                              booking.paymentStatus?.toLowerCase() === 'paid' || 
                              booking.paymentStatus?.toLowerCase() === 'held_by_admin') && (
                              <>
                                <button
                                  onClick={() => handleReleaseToVenue(booking)}
                                  disabled={isProcessing}
                                  style={{
                                    padding: '6px 12px',
                                    backgroundColor: '#10b981',
                                    color: 'white',
                                    border: 'none',
                                    borderRadius: '6px',
                                    cursor: isProcessing ? 'not-allowed' : 'pointer',
                                    fontSize: '12px',
                                    fontWeight: '600'
                                  }}
                                >
                                  Release to Venue
                                </button>
                                <button
                                  onClick={() => handleRefund(booking)}
                                  disabled={isProcessing || !canRefund(booking)}
                                  style={{
                                    padding: '6px 12px',
                                    backgroundColor: canRefund(booking) ? '#ef4444' : '#d1d5db',
                                    color: 'white',
                                    border: 'none',
                                    borderRadius: '6px',
                                    cursor: (isProcessing || !canRefund(booking)) ? 'not-allowed' : 'pointer',
                                    fontSize: '12px',
                                    fontWeight: '600'
                                  }}
                                  title={!canRefund(booking) ? 'Refund not allowed (less than 24 hours)' : 'Process refund'}
                                >
                                  Refund
                                </button>
                              </>
                            )}
                            {booking.paymentStatus?.toLowerCase() === 'released_to_venue' && (
                              <span style={{ fontSize: '12px', color: '#059669', fontWeight: '600' }}>
                                ✓ Released
                              </span>
                            )}
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};

export default AdminPaymentManagement;


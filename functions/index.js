// Firebase Cloud Function to handle Billplz payment callbacks
// Deploy this as a Cloud Function

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.billplzCallback = functions.https.onRequest(async (req, res) => {
  try {
    // Billplz sends payment updates via POST
    if (req.method !== 'POST') {
      return res.status(405).send('Method Not Allowed');
    }

    // Get Billplz callback data
    const {
      id: billId,
      collection_id: collectionId,
      paid,
      state,
      amount,
      paid_amount: paidAmount,
      due_at: dueAt,
      email,
      mobile,
      name,
      url,
      paid_at: paidAt,
      transaction_id: transactionId,
      transaction_status: transactionStatus,
      'x_signature': signature,
    } = req.body;

    console.log('Billplz callback received:', { billId, paid, state, transactionId });

    // TODO: Verify signature for security
    // const isValid = verifyBillplzSignature(req.body, signature);
    // if (!isValid) {
    //   return res.status(401).send('Invalid signature');
    // }

    // Get metadata from Billplz (reference_1 and reference_2)
    const bookingId = req.body.reference_1 || null;
    const bookingType = req.body.reference_2 || 'court'; // 'court' or 'coach'

    if (!bookingId) {
      console.error('No booking ID in callback');
      return res.status(400).send('Missing booking ID');
    }

    const db = admin.firestore();
    const isPaid = paid === 'true' || paid === true;

    // Determine which collection to update
    const collectionName = bookingType === 'coach' ? 'coach_appointments' : 'bookings';
    const bookingRef = db.collection(collectionName).doc(bookingId);

    // Get the booking document
    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      console.error('Booking not found:', bookingId);
      return res.status(404).send('Booking not found');
    }

    const bookingData = bookingDoc.data();

    // Update booking based on payment status
    if (isPaid && state === 'paid') {
      // Payment successful
      await bookingRef.update({
        status: 'confirmed',
        paymentStatus: 'completed',
        paymentId: transactionId || billId,
        billplzBillId: billId,
        paidAmount: paidAmount ? parseInt(paidAmount) / 100 : null, // Convert from cents
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        transactionDetails: {
          transactionId,
          transactionStatus,
          billId,
          state,
          paidAt,
        },
      });

      console.log(`Payment confirmed for ${collectionName} ${bookingId}`);

      // Create notification for user
      await db.collection('notifications').add({
        userId: bookingData.userId,
        type: 'payment_success',
        title: 'Payment Successful',
        message: bookingType === 'coach'
          ? `Your coaching session payment has been confirmed. Session with ${bookingData.coachName} on ${bookingData.date}.`
          : `Your court booking payment has been confirmed. ${bookingData.venueName} on ${bookingData.date}.`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          bookingId,
          bookingType,
          amount: paidAmount ? parseInt(paidAmount) / 100 : null,
          transactionId,
        },
      });

      // If coach appointment, notify coach as well
      if (bookingType === 'coach') {
        await db.collection('notifications').add({
          userId: bookingData.coachId,
          type: 'booking_confirmed',
          title: 'Booking Payment Confirmed',
          message: `Payment confirmed for session with ${bookingData.studentName} on ${bookingData.date}.`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            bookingId,
            bookingType,
            amount: paidAmount ? parseInt(paidAmount) / 100 : null,
          },
        });
      }

    } else if (state === 'deleted' || state === 'expired') {
      // Payment failed or cancelled
      await bookingRef.update({
        status: 'cancelled',
        paymentStatus: 'failed',
        billplzBillId: billId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        transactionDetails: {
          billId,
          state,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });

      console.log(`Payment failed for ${collectionName} ${bookingId}`);

      // Notify user of payment failure
      await db.collection('notifications').add({
        userId: bookingData.userId,
        type: 'payment_failed',
        title: 'Payment Failed',
        message: bookingType === 'coach'
          ? 'Your coaching session payment could not be processed. Please try again.'
          : 'Your court booking payment could not be processed. Please try again.',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          bookingId,
          bookingType,
          state,
        },
      });
    }

    // Send success response to Billplz
    return res.status(200).json({
      success: true,
      message: 'Callback processed successfully',
    });

  } catch (error) {
    console.error('Error processing Billplz callback:', error);
    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Helper function to verify Billplz signature (implement based on your needs)
function verifyBillplzSignature(data, signature) {
  // Implement signature verification according to Billplz documentation
  // This is a security measure to ensure the callback is from Billplz
  // For now, return true - but IMPLEMENT THIS for production
  return true;
}

// Optional: Function to check payment status manually (can be called from app)
exports.checkPaymentStatus = functions.https.onCall(async (data, context) => {
  try {
    // Verify user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const { bookingId, bookingType = 'court' } = data;

    if (!bookingId) {
      throw new functions.https.HttpsError('invalid-argument', 'Booking ID is required');
    }

    const db = admin.firestore();
    const collectionName = bookingType === 'coach' ? 'coach_appointments' : 'bookings';
    const bookingRef = db.collection(collectionName).doc(bookingId);

    const bookingDoc = await bookingRef.get();
    if (!bookingDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Booking not found');
    }

    const bookingData = bookingDoc.data();

    // Verify the user owns this booking
    if (bookingData.userId !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized to check this booking');
    }

    return {
      success: true,
      status: bookingData.status,
      paymentStatus: bookingData.paymentStatus,
      paymentId: bookingData.paymentId,
    };

  } catch (error) {
    console.error('Error checking payment status:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});
// EmailService.js
import emailjs from '@emailjs/browser';

class EmailService {
  constructor() {
    // Replace these with your actual EmailJS credentials
    this.serviceId = 'service_x9cj01m';
    this.approvalTemplateId = 'template_sosdye4';
    this.rejectionTemplateId = 'template_oudzdn5';
    this.publicKey = 'MuMiE_B6MKL_qMAO6';

    // Initialize EmailJS
    emailjs.init(this.publicKey);
  }

  async sendApprovalEmail(venueData, password) {
    try {
      const templateParams = {
        owner_name: venueData.ownerName,
        venue_name: venueData.venueName,
        email: venueData.email,
        password: password,
        to_email: venueData.email
      };

      const response = await emailjs.send(
        this.serviceId,
        this.approvalTemplateId,
        templateParams
      );

      console.log('Approval email sent successfully:', response);
      return { success: true, response };
    } catch (error) {
      console.error('Failed to send approval email:', error);
      return { success: false, error };
    }
  }

  async sendRejectionEmail(venueData, rejectionReason) {
    try {
      const templateParams = {
        owner_name: venueData.ownerName,
        venue_name: venueData.venueName,
        email: venueData.email,
        rejection_reason: rejectionReason,
        to_email: venueData.email
      };

      const response = await emailjs.send(
        this.serviceId,
        this.rejectionTemplateId,
        templateParams
      );

      console.log('Rejection email sent successfully:', response);
      return { success: true, response };
    } catch (error) {
      console.error('Failed to send rejection email:', error);
      return { success: false, error };
    }
  }

  // Test email functionality
  async sendTestEmail(recipientEmail) {
    try {
      const templateParams = {
        owner_name: 'Test User',
        venue_name: 'Test Venue',
        email: recipientEmail,
        password: 'TestPassword123',
        to_email: recipientEmail
      };

      const response = await emailjs.send(
        this.serviceId,
        this.approvalTemplateId,
        templateParams
      );

      return { success: true, response };
    } catch (error) {
      return { success: false, error };
    }
  }
}

export default new EmailService();
const nodemailer = require('nodemailer');

const { config } = require('./config');

let smtpTransporter;

function isLandingContactMailConfigured() {
  return Boolean(config.smtpHost && config.smtpUser && config.smtpPass);
}

async function sendLandingDemoRequestEmail(request) {
  if (!isLandingContactMailConfigured()) {
    return { sent: false, skipped: 'smtp_not_configured' };
  }

  const message = buildLandingDemoRequestEmail(request);
  const transporter = getSmtpTransporter();
  await transporter.sendMail(message);
  return { sent: true };
}

function getSmtpTransporter() {
  if (!smtpTransporter) {
    smtpTransporter = nodemailer.createTransport({
      host: config.smtpHost,
      port: config.smtpPort,
      secure: config.smtpSecure,
      auth: {
        user: config.smtpUser,
        pass: config.smtpPass,
      },
    });
  }
  return smtpTransporter;
}

function buildLandingDemoRequestEmail(request) {
  const name = sanitizeHeader(request.fullName || 'New lead');
  const storeType = storeTypeLabel(request.storeType);
  const createdAt = request.createdAt
    ? new Date(request.createdAt).toLocaleString('en-KE', {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: 'Africa/Nairobi',
      })
    : 'Just now';
  const lines = [
    `Name: ${request.fullName || '-'}`,
    `Email: ${request.email || '-'}`,
    `Store type: ${storeType}`,
    `Submitted: ${createdAt}`,
    '',
    'Message:',
    request.message || '-',
  ];

  return {
    from: config.smtpFromEmail,
    to: config.landingContactNotifyEmail,
    replyTo: request.email || undefined,
    subject: `New Piki POS demo request from ${name}`,
    text: lines.join('\n'),
    html: `
      <div style="font-family:Inter,Arial,sans-serif;line-height:1.5;color:#1f172b">
        <h2 style="margin:0 0 12px">New Piki POS demo request</h2>
        <p style="margin:0 0 18px;color:#5f556c">A customer submitted the landing page contact form.</p>
        <table style="border-collapse:collapse;width:100%;max-width:640px">
          ${rowHtml('Name', request.fullName)}
          ${rowHtml('Email', request.email)}
          ${rowHtml('Store type', storeType)}
          ${rowHtml('Submitted', createdAt)}
        </table>
        <h3 style="margin:22px 0 8px">Message</h3>
        <div style="white-space:pre-wrap;background:#f7f3ff;border:1px solid #eadfff;border-radius:10px;padding:14px">${escapeHtml(request.message || '-')}</div>
      </div>
    `,
  };
}

function rowHtml(label, value) {
  return `
    <tr>
      <td style="padding:9px 12px;border:1px solid #eadfff;background:#fbf9ff;font-weight:700;width:150px">${escapeHtml(label)}</td>
      <td style="padding:9px 12px;border:1px solid #eadfff">${escapeHtml(value || '-')}</td>
    </tr>
  `;
}

function storeTypeLabel(value) {
  const labels = {
    retail: 'Retail shop',
    pharmacy: 'Pharmacy',
    wholesale: 'Wholesale',
    service: 'Service business',
    other: 'Other',
  };
  return labels[value] || labels.other;
}

function sanitizeHeader(value) {
  return String(value || '')
    .replace(/[\r\n]+/g, ' ')
    .trim()
    .slice(0, 120);
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[char]));
}

module.exports = {
  buildLandingDemoRequestEmail,
  isLandingContactMailConfigured,
  sendLandingDemoRequestEmail,
};

const nodemailer = require('nodemailer');

const { config } = require('./config');

let smtpTransporter;

function isSmtpMailConfigured() {
  return Boolean(config.smtpHost && config.smtpUser && config.smtpPass);
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

function resolveSenderEmail(preferred) {
  const from =
    String(preferred || '').trim() ||
    config.smtpFromEmail ||
    config.otpFromEmail ||
    '';
  return from;
}

async function sendMail({ from, to, subject, text, html, replyTo, tags }) {
  if (!isSmtpMailConfigured()) {
    const error = new Error(
      'Email delivery is not configured. Set SMTP_HOST, SMTP_USER, and SMTP_PASS.',
    );
    error.status = 503;
    throw error;
  }

  const transporter = getSmtpTransporter();
  const message = {
    from: from || config.smtpFromEmail,
    to: Array.isArray(to) ? to.join(', ') : to,
    subject,
    text,
    html,
  };
  if (replyTo) message.replyTo = replyTo;
  if (Array.isArray(tags) && tags.length > 0) {
    message.headers = {
      'X-Email-Tags': tags
        .map((tag) =>
          tag && typeof tag === 'object' && tag.name && tag.value
            ? `${tag.name}=${tag.value}`
            : String(tag),
        )
        .join(', '),
    };
  }

  try {
    await transporter.sendMail(message);
  } catch (error) {
    const wrapped = new Error(
      `SMTP delivery failed: ${error?.message || 'unknown error'}`,
    );
    wrapped.status = 502;
    wrapped.cause = error;
    throw wrapped;
  }
}

module.exports = {
  isSmtpMailConfigured,
  getSmtpTransporter,
  resolveSenderEmail,
  sendMail,
};

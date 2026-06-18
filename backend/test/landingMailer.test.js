const test = require('node:test');
const assert = require('node:assert/strict');

process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/test';
process.env.SUPPORT_EMAIL = 'support@pikipos.com';
process.env.LANDING_CONTACT_NOTIFY_EMAIL = 'support@pikipos.com';

const { buildLandingDemoRequestEmail } = require('../src/landingMailer');

test('landing demo request email formats lead details safely', () => {
  const message = buildLandingDemoRequestEmail({
    fullName: 'Jane <Owner>',
    email: 'jane@example.com',
    storeType: 'service',
    message: 'Need setup help for <main branch>',
    createdAt: '2026-06-18T08:00:00.000Z',
  });

  assert.equal(message.to, 'support@pikipos.com');
  assert.equal(message.replyTo, 'jane@example.com');
  assert.match(message.subject, /Jane <Owner>/);
  assert.match(message.text, /Store type: Service business/);
  assert.match(message.html, /Jane &lt;Owner&gt;/);
  assert.match(message.html, /Need setup help for &lt;main branch&gt;/);
});

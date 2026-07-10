'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import {
  CustomerPortalPayment,
  CustomerPortalStatement,
  fetchCustomerPortalPayment,
  fetchCustomerPortalStatement,
  requestCustomerPortalCode,
  signInCustomerPortal,
  startCustomerPortalMpesaPayment,
} from '@/lib/api';

const inputClass = 'w-full rounded-lg border border-border-strong bg-background px-3 py-2.5 text-sm text-foreground outline-none transition placeholder:text-muted focus:border-accent';

function money(value: number) {
  return new Intl.NumberFormat('en-KE', {
    style: 'currency',
    currency: 'KES',
    maximumFractionDigits: 2,
  }).format(Number(value || 0));
}

export default function CustomerPortalPage() {
  const [businessId, setBusinessId] = useState('');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [codeSent, setCodeSent] = useState(false);
  const [token, setToken] = useState('');
  const [statement, setStatement] = useState<CustomerPortalStatement | null>(null);
  const [amount, setAmount] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [payment, setPayment] = useState<CustomerPortalPayment | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadStatement = useCallback(async (sessionToken: string) => {
    const data = await fetchCustomerPortalStatement(sessionToken);
    setStatement(data);
    setAmount(String(Number(data.customer.balance || 0).toFixed(2)));
  }, []);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    setBusinessId(params.get('businessId') || '');
  }, []);

  useEffect(() => {
    if (!token || !payment || !['pending', 'processing'].includes(payment.status)) return;
    const timer = window.setInterval(async () => {
      try {
        const updated = await fetchCustomerPortalPayment(token, payment.id);
        setPayment(updated);
        if (updated.status === 'paid') await loadStatement(token);
      } catch {
        // A temporary network problem should not sign the customer out.
      }
    }, 5000);
    return () => window.clearInterval(timer);
  }, [loadStatement, payment, token]);

  async function requestCode(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const result = await requestCustomerPortalCode(businessId.trim(), email.trim());
      setCodeSent(true);
      setMessage(result.sent === false
        ? `Please wait ${result.retryAfterSeconds || 60} seconds before requesting another code.`
        : 'If this email is linked to an account, a verification code is on its way.');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to send the verification code.');
    } finally {
      setBusy(false);
    }
  }

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const result = await signInCustomerPortal(businessId.trim(), email.trim(), code.trim());
      setToken(result.token);
      await loadStatement(result.token);
      setMessage(null);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to sign in.');
    } finally {
      setBusy(false);
    }
  }

  async function startPayment(event: FormEvent) {
    event.preventDefault();
    const value = Number(amount);
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const started = await startCustomerPortalMpesaPayment(token, value, phoneNumber.trim());
      setPayment(started);
      setMessage('Check your phone and approve the M-Pesa prompt. This page will update once it is confirmed.');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to start the M-Pesa payment.');
    } finally {
      setBusy(false);
    }
  }

  function signOut() {
    setToken('');
    setStatement(null);
    setPayment(null);
    setCode('');
    setMessage(null);
    setError(null);
  }

  const outstanding = Number(statement?.customer.balance || 0);

  return (
    <main className="min-h-screen bg-background px-4 py-10 sm:px-6">
      <div className="mx-auto w-full max-w-3xl">
        <a href="/" className="text-sm text-muted-strong transition hover:text-foreground">← Back to shop</a>
        <div className="mt-6 rounded-2xl border border-border-subtle bg-surface p-6 shadow-2xl sm:p-8">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-muted">Customer self-service</p>
          <h1 className="mt-2 font-display text-4xl tracking-tight">Your account</h1>
          <p className="mt-2 max-w-xl text-sm leading-6 text-muted-strong">View your outstanding statements and pay securely with M-Pesa.</p>

          {error && <p className="mt-5 rounded-lg border border-red-400/30 bg-red-400/10 px-3 py-2 text-sm text-red-200">{error}</p>}
          {message && <p className="mt-5 rounded-lg border border-emerald-400/30 bg-emerald-400/10 px-3 py-2 text-sm text-emerald-100">{message}</p>}

          {!statement ? (
            <div className="mt-8 max-w-md">
              {!codeSent ? (
                <form onSubmit={requestCode} className="space-y-4">
                  <label className="block text-sm font-medium text-muted-strong">Business ID<input required value={businessId} onChange={(event) => setBusinessId(event.target.value)} placeholder="Your store's business ID" className={`mt-1.5 ${inputClass}`} /></label>
                  <label className="block text-sm font-medium text-muted-strong">Email address<input required type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" className={`mt-1.5 ${inputClass}`} /></label>
                  <button disabled={busy} className="w-full rounded-lg bg-accent px-4 py-3 text-sm font-semibold text-background disabled:opacity-60">{busy ? 'Sending…' : 'Email me a code'}</button>
                </form>
              ) : (
                <form onSubmit={signIn} className="space-y-4">
                  <p className="text-sm text-muted-strong">Enter the six-digit code sent to {email}.</p>
                  <label className="block text-sm font-medium text-muted-strong">Verification code<input required inputMode="numeric" maxLength={6} value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, ''))} placeholder="123456" className={`mt-1.5 ${inputClass}`} /></label>
                  <button disabled={busy} className="w-full rounded-lg bg-accent px-4 py-3 text-sm font-semibold text-background disabled:opacity-60">{busy ? 'Signing in…' : 'View my statement'}</button>
                  <button type="button" onClick={() => setCodeSent(false)} className="w-full text-sm text-muted transition hover:text-foreground">Use a different email</button>
                </form>
              )}
            </div>
          ) : (
            <div className="mt-8 space-y-8">
              <div className="flex flex-wrap items-start justify-between gap-4 rounded-xl border border-border-subtle bg-background/50 p-5">
                <div><p className="text-sm text-muted">Signed in as</p><p className="mt-1 text-xl font-semibold">{statement.customer.name}</p><p className="mt-1 text-sm text-muted">{statement.customer.email}</p></div>
                <button onClick={signOut} className="rounded-lg border border-border-strong px-3 py-2 text-sm text-muted-strong transition hover:text-foreground">Sign out</button>
              </div>

              <section className="grid gap-5 lg:grid-cols-[1.15fr_0.85fr]">
                <div className="rounded-xl border border-border-subtle p-5"><p className="text-sm text-muted">Outstanding balance</p><p className="mt-2 font-display text-4xl">{money(outstanding)}</p><p className="mt-2 text-sm text-muted">{statement.sales.length} open statement{statement.sales.length === 1 ? '' : 's'}</p></div>
                <form onSubmit={startPayment} className="rounded-xl border border-border-subtle p-5 space-y-3"><h2 className="font-display text-2xl">Pay with M-Pesa</h2><label className="block text-sm text-muted-strong">Amount<input required min="1" max={outstanding} step="0.01" type="number" value={amount} onChange={(event) => setAmount(event.target.value)} className={`mt-1.5 ${inputClass}`} /></label><label className="block text-sm text-muted-strong">M-Pesa phone number<input required value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} placeholder="0712 345 678" className={`mt-1.5 ${inputClass}`} /></label><button disabled={busy || outstanding <= 0} className="w-full rounded-lg bg-accent px-4 py-3 text-sm font-semibold text-background disabled:opacity-60">{busy ? 'Starting payment…' : 'Send M-Pesa prompt'}</button></form>
              </section>

              {payment && <section className="rounded-xl border border-border-subtle bg-background/40 p-5"><p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">Latest payment</p><p className="mt-2 text-lg font-semibold capitalize">{payment.status.replace(/_/g, ' ')}</p><p className="mt-1 text-sm text-muted">{money(payment.amount)} · {payment.receiptNumber ? `Receipt ${payment.receiptNumber}` : 'Awaiting M-Pesa confirmation'}</p>{payment.status === 'paid' && payment.unappliedAmount > 0 && <p className="mt-2 text-sm text-amber-200">{money(payment.unappliedAmount)} requires staff follow-up before it can be applied.</p>}</section>}

              <section><h2 className="font-display text-2xl">Open statements</h2><div className="mt-4 overflow-hidden rounded-xl border border-border-subtle">{statement.sales.length === 0 ? <p className="p-5 text-sm text-muted">You have no outstanding statements.</p> : statement.sales.map((sale) => <div key={sale.id} className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle px-5 py-4 last:border-0"><div><p className="font-medium">Statement #{sale.id.slice(0, 8)}</p><p className="mt-1 text-sm text-muted">{new Date(sale.created_at).toLocaleDateString('en-KE')}{sale.due_date ? ` · Due ${new Date(sale.due_date).toLocaleDateString('en-KE')}` : ''}</p></div><div className="text-right"><p className="font-semibold">{money(Number(sale.balance_due))}</p><p className="mt-1 text-xs text-muted">of {money(Number(sale.total_amount))}</p></div></div>)}</div></section>
            </div>
          )}
        </div>
      </div>
    </main>
  );
}

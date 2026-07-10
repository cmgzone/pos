# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/

# workflow
- For major features, provide a structured implementation plan first, then wait for "PLEASE IMPLEMENT THIS PLAN:" before executing. Confidence: 0.85
- After any significant implementation, deploy to GitHub and migrate the database to Neon. Confidence: 0.85
- After implementing new features, provide a clear explanation of how users will use them (user-flow / user journey). Confidence: 0.70

# ui-ux
- Design all screens mobile-first — avoid congested, busy layouts on mobile; use clean, breathable spacing. Confidence: 0.80

# error-handling
- Never show raw developer error messages to end users. Polish all error messages across the app to be user-friendly. Confidence: 0.75

# business-logic
- Piki POS targets the Kenyan market: currency is KES, payments use M-Pesa (Safaricom Daraja API), and compliance includes KRA/eTIMS. Confidence: 0.75
- All features (branches, employees, AI seats, selling modes, reports) must be gated by subscription plans configured by the super admin. Confidence: 0.80

# analysis
- When asked "how good is this" or "compare with X", provide an honest, critical assessment including weaknesses and missing pieces vs competitors like Forty POS. Confidence: 0.70


# Edge-case verification
Current rebuilt tests and supplied runtime evidence cover the objective's listed applicable edge cases.

| Case | Runtime evidence |
|---|---|
| Multiple items, payment attempts, split payment, retry | Actual-module integration fixture; INT01 and reconciliation PASS |
| Full, partial, rejected returns/refunds | Clean small/large DQ and actual E; 14 reconciliation PASS |
| Completed split refund, failed attempt excluded, pending split not settled | Targeted REF01–03 PASS |
| Partial-quantity and repeated returns | Targeted REF04 + 36 fixture integrity checks PASS |
| Zero-price item and zero denominator | Targeted EDGE06–07 PASS; actual G output |
| Fractional refund and residual rounding | FIN01–07 + edge item refunds + exact-cent reconciliation PASS |
| Identical timestamps and channel acquisition | EDGE05 PASS, actual G |
| Customers without purchases | EDGE08 PASS, actual D |
| Same-month purchases, distinct retention customer | EDGE01 PASS, actual G |
| Missing months zero and future NULL | EDGE02–03 PASS, actual G |
| Year boundary | COH03 regression PASS; seeded multi-year A–G and reconciliation run |
| Partial observation month | EDGE04 PASS with Sep 15 cutoff, actual G |
| Below/equal/above 48/72/120-hour SLA | Nine targeted actual F assertions PASS; SLA01–10 math regression PASS |

The full raw outputs are preserved in a separate local audit ZIP. [test_report.md](test_report.md) summarizes the observed results; executable regression/integration/targeted fixtures remain in tests/. These finite tests prove the specified fixtures, not arbitrary future data or production scalability. Corrected harness-failure history is retained in the audit archive rather than the portfolio.

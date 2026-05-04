# Appendix V: FR 2052a Double Counting of Certain Exposures

> **hand-curated.** Content preserved verbatim from the source PDF;
> the only edit is removal of trailing references to Appendices VI,
> VII, and VIII (which live in their own files). The fenced block
> below retains the original column alignment. See
> [`human-annotations.md`](../../human-annotations.md) for notes.


The FR 2052a instructions state that, as a general rule, transactions should not be reported twice in a
single submission. However, there are certain exceptions to this rule and this document outlines the
instances when it is acceptable. This appendix provides indicative guidance on cases where double-
counting is generally appropriate and expected. The items listed below may not be exhaustive, and may
have exceptions. Consult with the applicable supervisory and regulatory reporting teams for additional
guidance on potential exceptions.

1. All third-party exposures at subsidiaries that are designated reporting entities, as
    these will be, at a minimum, reported for both the consolidated reporting entity and all
    applicable reporting entities that comprise the consolidated firm.

2. Collateral swaps, as each transaction will be reported in both the Inflows-Secured and
    Outflows-Secured tables (albeit from different perspectives).

3. Collateral that has been received via a secured lending transaction and pre-positioned
    at a central bank or GSE, as these assets should appear in the I.S table (note that the
    [Unencumbered] flag must be set to false) and under product I.A.2: Capacity.

4. Loans and leases, as these must be reported in the Inflows-Unsecured or Inflows-
    Secured tables by counterparty as well as in the appropriate product in the I.A table
    according to their market value.

5. Assets that are encumbered to financing transactions and derivatives, as these must
    be reported under I.A.7: Encumbered Assets and the value of these positions must also
    be reported under the product to which they are encumbered in the O.W, O.S or S.DC
    tables (i.e., using the [Collateral Value] or [Market Value] fields).

6. Unsecured derivatives cash flows occurring over the next 30 days, as these must be
    reported under products I.O.1: Derivatives Receivables or O.O.1: Derivatives Payables
    and must be included in the calculation of products I.O.7: Net 30-day Derivative
    Receivables or O.O.20: Net 30-day Derivative Payables.

7. Derivative collateral cash flows occurring over the next 30 days, as these must be
    reported under products I.O.2: Collateral Called for Receipt or O.O.2: Collateral Called
    for Delivery and must be included in the calculation of products I.O.7: Net 30-day
    Derivative Receivables or O.O.20: Net 30-day Derivative Payables.

8. Foreign exchange transactions maturing over the next 30 days, as these must be
    reported under products S.FX.1: Spot, S.FX.2: Forwards and Futures, and S.FX.3: Swaps
    and must be included in the calculation of products I.O.7: Net 30-day Derivative
    Receivables or O.O.20: Net 30-day Derivative Payables.

9. Forward purchases and sales of securities maturing over the next 30 days, as these
    purchases must be reported under I.A.6: Forward Asset Purchases and sales must be
    reported under O.S.8: Firm Shorts, with a [Sub-Product] of “Unsettled (Forward)”, and
    both must be included in the calculation of products I.O.7: Net 30-day Derivative
    Receivables or O.O.20: Net 30-day Derivative Payables.

10. Structured and non-structured debt maturing beyond 30 days where the reporting
    firm is the primary market maker, as these balances will be reported in one of the
    Outflows-Wholesale products and in S.L.4: Non-Structured Debt Maturing in Greater
    than 30-days – Primary Market Maker or S.L.5: Structured Debt Maturing in Greater
    than 30-days – Primary Market Maker.

11. O.O.13-O.O.16: Total Collateral Required Due to a Downgrade/Change in Financial
    Condition, as the various downgrade levels are meant to reflect a cumulative impact.
    This concept is illustrated by the inequalities below:

    Total Collateral Required Due to a:

     1 Notch Downgrade ≤ 2 Notch Downgrade ≤ 3 Notch Downgrade ≤ Change in Financial Condition

12. O.O.9-O.O.12: Loss of Re-hypothecation Rights Due to a Downgrade/Change in
    Financial Condition, as the various downgrade levels are meant to reflect the
    cumulative impact. This concept is illustrated by the inequalities below:

    Loss of Re-hypothecation Rights Due to a:

     1 Notch Downgrade ≤ 2 Notch Downgrade ≤ 3 Notch Downgrade ≤ Change in Financial Condition

13. I.O.2: Collateral called for Receipt with a [Maturity Bucket] = “Open”, as collateral that
    is both called for and received on the reporting date T should be also reported in the
    stock of S.DC.7: Initial Margin Received or S.DC.10: Variation Margin Received.

14. O.O.2: Collateral called for Delivery with a [Maturity Bucket] = “Open”, as collateral
    that is both called for and posted on the reporting date T should be also be reported in
    the stock of S.DC.5: Initial Margin Posted- House or S.DC.6: Initial Margin Posted –


    Customer or S.DC.8: Variation Margin Posted – House or S.DC.9: Variation Margin
    Posted - Customer.
15. S.DC.14: Collateral Disputes Receivables and I.O.2: Collateral Called for Receipt, since
    an amount in dispute should be reflected in both products.

16. S.DC.13: Collateral Disputes Deliverables and O.O.2: Collateral Called for Delivery,
    since an amount in dispute should be reflected in both products.

17. S.DC.17: Sleeper Collateral Receivables, as the amount due to a reporting entity but not
    yet called for will also be included in the total amount of S.DC.5: Initial Margin Posted –
    House, S.DC.6: Initial Margin Posted – Customer, S.DC.8: Variation Margin Posted –
    House or S.DC.9: Variation Margin Posted - Customer.

18. S.DC.15: Sleeper Collateral Deliverables, as the amount due to a reporting firm’s
    counterparties that has not yet been called for should also be included in the total
    amount of S.DC.7: Initial Margin Received or S.DC.10: Variation Margin Received.

19. S.L.1: Subsidiary Liquidity That Cannot Be Transferred, S.L.2: Subsidiary Liquidity
    Available for Transfer, S.L.7: Subsidiary Funding That Cannot Be Transferred, S.L.8:
    Subsidiary Funding Available for Transfer and S.I.6: Subsidiary Liquidity Not
    Transferrable should correspond to asset and liability amounts reported elsewhere on
    the FR 2052A submission.

20. O.D.12: Other Product Sweep Accounts includes balances that are swept from deposit
    accounts into other products or other types of deposits accounts. These balances should
    be reported in both the product that corresponds with the contractual liability into
    which the funds are swept as of close of business on the reporting date, as well as
    O.D.12.

21. I.O.8: Principal Payments on Unencumbered Investment Securities, as the market
    value of these securities must also be reported in the I.A.1: Unencumbered Assets or
    I.A.2: Capacity products.


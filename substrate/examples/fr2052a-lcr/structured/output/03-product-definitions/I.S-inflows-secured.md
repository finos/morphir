# I.S: Inflows-Secured


General Guidance: Report the contractual principal payments to be received. Exclude non-
performing loans (i.e., 90-days past due or non-accrual), which are instead reported in
Supplemental-Balance Sheet table. Report the fair (market) value of the pledged securities
using the Collateral Value field. Report on a gross basis; do not net borrowings against loans
unless the transactions contractually settle on a net basis. FIN 41 does not apply for this report.
If an amortizing loan is underwritten on a forward‐starting basis, the amount reported in the
[Forward Start Amount] field, representing the initial disbursement of the loan, should be split
across all associated products and should match the corresponding maturity amount (i.e., the
principal payment received for that period).

Asset Category: For transactions that allow for collateral agreement amendments, report the
transaction based on the actual stock of collateral held as of the as-of date (T).

For all products, use the [Counterparty] field to further identify the type of borrower as one of
the following:


- Retail
- Small Business
- Non-Financial Corporate
- Sovereign
- Central Bank
- GSE
- PSE
- MDB
- Other Supranational
- Pension Fund
- Bank
- Broker-Dealer
- Investment Company or Advisor
- Financial Market Utility
- Other Supervised Non-Bank Financial Entity
- Debt Issuing SPE
- Non-Regulated Fund
- Other

The following is a list of products to be reported in the Inflows-Secured table:

### I.S.1: Reverse Repo

Refers to all reverse repurchase agreements (including under Master Repurchase Agreement or
Global Master Repurchase Agreements).

### I.S.2: Securities Borrowing

Refers to all securities borrowing transactions (including under Master Securities Loan
Agreements).

### I.S.3: Dollar Rolls

Refers to transactions using “To Be Announced” (TBA) contracts with the intent of providing
financing for a specific security or pool of collateral. Report transactions where the reporting
entity has agreed to buy the TBA contract and sell it back at a later date.

### I.S.4: Collateral Swaps

Refers to transactions where non-cash assets are exchanged (e.g., collateral
upgrade/downgrade trades) at the inception12 of the transaction, or a non-cash asset is

12 Collateral swap transactions that are remargined with cash payments should continue to be reported under this
product.


borrowed and no collateral is posted (i.e., an unsecured borrowing of collateral), and the assets
will be returned at a future date.

For collateral swaps where there is an exchange of non-cash assets, split the collateral swap
into two separate borrowing and lending transactions and report in both the Inflows-Secured
and Outflows-Secured tables. I.S.4 should reflect the borrowing leg of the transaction. Report
the [Collateral Class] according to the assets received. Report the fair value under GAAP of the
assets received in the [Collateral Value] field. Report the fair value under GAAP of the assets
pledged in the [Maturity Amount] field. Use the [Sub-Product] field to identify the type of
collateral pledged based on the asset categories defined in the LRM Standards:

- Level 1 Pledged
- Level 2a Pledged
- Level 2b Pledged
- Non-HQLA Pledged
- No Collateral Pledged

For collateral swaps where a non-cash asset is borrowed, report the [Collateral Class] according
to the assets received and report the fair value under GAAP of the assets received in the
[Collateral Value] field.

### I.S.5: Margin Loans

Refers to credit provided to a client to fund a trading position, collateralized by the client’s cash
or security holdings. Report margin loans on a gross basis; do not net client debits and credits.

### I.S.6: Other Secured Loans - Rehypothecatable

Refers to all other secured lending that does not otherwise meet the definitions of the Inflows-
Secured products listed above and is not drawn from a revolving facility, for which the collateral
received is contractually rehypothecatable. Use the comments table to provide a general
description of secured loans included in this product on at least a monthly basis and in the
event of a material change in reported values.

### I.S.7: Outstanding Draws on Secured Revolving Facilities

Refers to the existing loan arising from the drawn portion of a revolving facility (e.g., a general
working capital facility) extended by the reporting entity, where the facility is secured by a lien
on an asset or pool of assets.


### I.S.8: Other Secured Loans - Non-Rehypothecatable

Refers to all other secured lending that does not otherwise meet the definitions of the Inflows-
Secured products listed above, for which the collateral received is not contractually
rehypothecatable. Use the comments table to provide a general description of other loans
included in this product on at least a monthly basis and in the event of a material change in
reported values.

### I.S.9: Synthetic Customer Longs

Refers to total return swaps booked in client accounts, where the reporting entity is
economically short the underlying reference asset and the client is economically long. Use the
[Maturity Bucket] to designate the latest date a transaction could be unwound or terminated
after taking into account clients’ contractual rights to delay termination. Use the [Collateral
Class] field to designate the reference asset of the transaction. Use the following [Sub-Product]
values to designate how the position is “funded” (i.e., hedged):

- Physical Long Position  Refers to transactions hedged with physical long positions. In the event the long position that has been encumbered to another transaction, use the [Effective Maturity Bucket] to indicate the period of the encumbrance. For long positions held unencumbered, set the [Unencumbered] flag to “Y”.

- Synthetic Customer Short  Refers to transactions where the customer synthetic long is hedged with another customer’s synthetic short position reported in O.S.9.

- Synthetic Firm Financing  Refers to transactions where the associated hedge meets the definition of O.S.10.

- Futures  Refers to transactions hedged with futures contracts.

- Other  Refers to all other methods of hedging.

- Unhedged  Refers to positions that are not economically hedged with another instrument or transaction.

### I.S.10: Synthetic Firm Sourcing

Refers to total return swaps that are not booked in client accounts, where the reporting entity
is economically short the underlying reference asset and the counterparty is economically long.
Use the [Maturity Bucket] to designate the earliest date a transaction could be unwound or
terminated. Use the [Collateral Class] field to designate the reference asset of the transaction.


Use the following [Sub-Product] values to designate how the position is “covered” (i.e.,
hedged):

- Physical Long Position  Refers to transactions hedged with physical long positions. In the event the long position that has been encumbered to another transaction, use the [Effective Maturity Bucket] to indicate the period of the encumbrance. For long positions held unencumbered, set the [Unencumbered] flag to “Y”.

- Synthetic Customer Short  Refers to transactions hedged with a customer’s synthetic short position reported in O.S. 9.

- Synthetic Firm Financing  Refers to transactions where the associated hedge meets the definition of O.S.10.

- Futures  Refers to transactions hedged with futures contracts.

- Other  Refers to all other methods of hedging.

- Unhedged  Refers to positions that are not economically hedged with another instrument or transaction.

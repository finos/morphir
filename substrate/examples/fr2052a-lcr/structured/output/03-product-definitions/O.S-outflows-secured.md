# O.S: Outflows-Secured


General Guidance: For all products outlined in this table, report the contractual principal cash
payment to be paid at maturity, excluding interest payments (which should be reported under
product O.O.19, using the Maturity Amount field). Report the fair value under GAAP of the
pledged securities using the Collateral Value field. Report on a gross basis; do not net
borrowings against loans. FIN 41 does not apply for this report.

For collateral class, report the type of collateral financed according to the Asset Category Table
(Appendix III). For transactions that allow for collateral agreement amendments, report the
transaction based on the collateral pledged as of date T.

Use the [Counterparty] field to indicate the type of counterparty for each data element:

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

The following is a list of product transactions to be reported in the Outflows-Secured table:

### O.S.1: Repo

Refers to all repurchase agreements (including under Master Repurchase Agreements or Global
Master Repurchase Agreements).

### O.S.2: Securities Lending

Refers to all securities lending transactions (including under Master Securities Loan
Agreements).

### O.S.3: Dollar Rolls

Refers to transactions using TBA contracts with the intent of financing a security or pool of
collateral. Report transactions where the reporting entity has agreed to sell the TBA contract
and buy it back at a later date.

### O.S.4: Collateral Swaps

Refers to transactions where non-cash assets are exchanged (e.g., collateral
upgrade/downgrade trades) at the inception14 of the transaction, or a non-cash asset is lent
and no collateral is received (i.e., an unsecured loan of collateral), and the assets will be
returned at a future date.

For collateral swaps where non-cash assets are exchanged, split the collateral swap into two
separate lending and borrowing transactions and report in both the Outflows-Secured and

14 Collateral swap transactions that are remargined with cash payments should continue to be reported under this
product.


Inflows-Secured tables. O.S.4 should be reported based on the collateral pledged. Report the
[Collateral Class] according to the assets pledged. Report the fair value of these assets pledged
in the [Collateral Value] field. Report the fair value of assets received in the [Maturity Amount]
field. Use the [Sub-Product] field to identify the type of collateral received based on the asset
categories defined in the LRM Standards:

- Level 1 Received
- Level 2a Received
- Level 2b Received
- Non-HQLA Received
- No Collateral Received

For collateral swaps where a non-cash asset is lent, report the [Collateral Class] according to the
assets pledged and report the fair value of these assets pledged in the [Collateral Value] field.

### O.S.5: FHLB Advances

Refers to outstanding secured funding sourced from the FHLBs. The amount borrowed and the
fair value of collateral pledged to secure the borrowing should not be included under product
I.A.2: Capacity with [Counterparty] field set to “GSE”.

### O.S.6: Exceptional Central Bank Operations

Refers to outstanding secured funding from central banks for exceptional central bank
operations. Do not include transactions related to normal open market operations, which
should be reported based on the transaction type (e.g., O.S.1: Repo) with the [Counterparty]
field set to “Central Bank”. The amount borrowed and the fair value of collateral pledged to
secure the borrowing should not be included under product I.A.2: Capacity.

Use the [Sub-Product] field to further identify the specific source of secured funding provided
according to the following groupings:

- FRB (Federal Reserve Bank)
- SNB (Swiss National Bank)
- BOE (Bank of England)
- ECB (European Central Bank)
- BOJ (Bank of Japan)
- RBA (Reserve Bank of Australia)
- BOC (Bank of Canada)
- OCB (Other Central Bank)
- FRFF (Covered Federal Reserve Facility Funding)


### O.S.7: Customer Shorts

Refers to a transaction where the reporting entity’s customer sells a physical security it does
not own, and the entity subsequently obtains the same security from an internal or external
source to make delivery into the sale. External refers to a transaction with a counterparty that
falls outside the scope of consolidation for the reporting entity. Internal refers to securities
sourced from within the scope of consolidation of the reporting entity.

Use the [Sub-Product] field to further identify the appropriate source for delivery into the sale
according to the following categories:

- External Cash Transactions  Refers to securities sourced through a securities borrowing, reverse repo, or like transaction in exchange for cash collateral.

- External Non-Cash Transactions  Refers to securities sourced through a collateral swap or like transaction in exchange for non-cash collateral.

- Firm Longs  Refers to securities sourced internally from the reporting entity’s own inventory of collateral where the sale does not coincide with an offsetting performance-based swap derivative.

- Customer Longs  Refers to securities sourced internally from collateral held in customer accounts at the reporting entity.

- Unsettled - Regular Way  Refers to sales that meet the definition of regular-way securities trades under GAAP, that have been executed, but not yet settled and therefore have not been covered. Use the [Forward Start Amount] and [Forward Start Bucket] fields to indicate the settlement amount and settlement date of the securities sold. Report failed settlements with a [Forward Start Bucket] value of “Open”.

- Unsettled - Forward Refers to sales that do not meet the definition of regular-way securities trades, that have been executed, but not yet settled and therefore have not been covered. Use the [Forward Start Amount] and [Forward Start Bucket] fields to indicate the settlement amount and settlement date of the securities sold. Report failed settlements with a [Forward Start Bucket] value of “Open”.

Note that the [Sub-Product] designation may differ between the Consolidated Firm reporting
entity and a subsidiary reporting entity if the collateral delivered into the short is sourced from,
for example, an affiliate’s long inventory. For the subsidiary reporting entity, collateral sourced


from an affiliate should be represented as sourced from an external transaction; however for
the consolidated firm, this would be represented as sourced from a “Firm Long” position.

### O.S.8: Firm Shorts

Refers to a transaction where the reporting entity sells a security it does not own, and the
entity subsequently obtains the same security from an internal or external source to make
delivery into the sale. External refers to a transaction with a counterparty that falls outside the
scope of consolidation for the reporting entity. Internal refers to securities sourced from within
the scope of consolidation of the reporting entity.

Use the [Sub-Product] field to further identify the appropriate source for delivery into the sale
according to the following categories:

- External Cash Transactions  Refers to securities sourced through a securities borrowing, reverse repo, or like transaction in exchange for cash collateral.

- External Non-Cash Transactions  Refers to securities sourced through a collateral swap or like transaction in exchange for non-cash collateral.

- Firm Longs  Refers to securities sourced internally from the reporting entity’s own inventory of collateral where the sale does not coincide with an offsetting performance-based swap derivative.

- Customer Longs  Refers to securities sourced internally from collateral held in customer accounts at the reporting entity.

- Unsettled - Regular Way  Refers to sales that meet the definition of regular-way securities trades under GAAP, that have been executed, but not yet settled and therefore have not been covered. Use the [Forward Start Amount] and [Forward Start Bucket] fields to indicate the settlement amount and settlement date of the securities sold. Report failed settlements with a [Forward Start Bucket] value of “Open”.

- Unsettled - Forward  Refers to sales that do not meet the definition of regular-way securities trades, that have been executed, but not yet settled and therefore have not been covered. These transactions should also be included in the calculation of products I.O.7: Net 30-day Derivative Receivables and O.O.20: Net 30-day Derivative Payables. Use the [Forward Start Amount] and [Forward Start Bucket] fields to indicate the settlement amount and settlement date of the


                      securities sold. Report failed settlements with a [Forward Start Bucket] value
                      of “Open”.

Note that the [Sub-Product] designation may differ between the Consolidated Firm reporting
entity and a subsidiary reporting entity if the collateral delivered into the short is sourced from,
for example, an affiliate’s long inventory. For the subsidiary reporting entity, collateral sourced
from an affiliate should be represented as sourced from an external transaction; however for
the consolidated firm, this would be represented as sourced from a “Firm Long” position.

### O.S.9: Synthetic Customer Shorts

Refers to total return swaps booked in client accounts, where the reporting entity is
economically long the underlying reference asset and the client is economically short. Use the
[Maturity Bucket] to designate the earliest date a transaction could be unwound or terminated.
Use the [Collateral Class] field to designate the reference asset of the transaction. Use the
following [Sub-Product] values to designate how the position is “covered” (i.e., hedged):

- Firm Short  Refers to transactions where the associated hedge is a short sale by the reporting entity of the physical security (i.e., transactions reportable under O.S.8, excluding those with a [Sub-Product] of “Firm Longs”.

- Synthetic Customer Long  Refers to transactions where the customer synthetic short is hedged with another customer’s synthetic long position reported in I.S.9.

- Synthetic Firm Sourcing  Refers to transactions where the associated hedge meets the definition of I.S.10.

- Futures  Refers to transactions hedged with futures contracts.

- Other  Refers to all other methods of hedging.

- Unhedged  Refers to positions that are not economically hedged with another instrument or transaction.

### O.S.10: Synthetic Firm Financing

Refers to a total return swaps that are not booked in client accounts, where the reporting entity
is economically long the underlying reference asset and the counterparty is economically short.
Use the [Maturity Bucket] to designate the earliest date a transaction could be unwound or
terminated. Use the [Collateral Class] field to designate the reference asset of the transaction.


Use the following [Sub-Product] values to designate how the position is “covered” (i.e.,
hedged):

- Firm Short  Refers to transactions where the associated hedge is a short sale by the reporting entity of the physical security (i.e., transactions reportable under O.S.8, excluding those with a [Sub-Product] of “Firm Longs”.

- Synthetic Customer Long  Refers to transactions hedged with a customer’s synthetic long position reported in I.S. 9.

- Synthetic Firm Sourcing  Refers to transactions where the associated hedge meets the definition of I.S.10.

- Futures  Refers to transactions hedged with futures contracts.

- Other  Refers to all other methods of hedging.

- Unhedged  Refers to positions that are not economically hedged with another instrument or transaction.

### O.S.11: Other Secured Financing Transactions

Refers to all other secured financing transactions that do not otherwise meet the definitions of
Outflows-Secured products listed above, and for which rehypothecation rights over the
collateral pledged are conferred to the reporting entity’s counterparty. Use the comments
table to provide a general description of other secured financing transactions included in
this product on at least a monthly basis and in the event of a material change in reported values.

# S.FX: Supplemental — Foreign Exchange


General Guidance:

U.S. firms that are identified as Category III banking organizations with average weighted short-
term wholesale funding of less than $75 billion; U.S. firms that are identified as Category IV
banking organizations; FBOs that are identified as Category III foreign banking organizations
with average weighted short-term wholesale funding of less than $75 billion; and FBOs that are
identified as Category IV foreign banking organizations are not required to report on this S.FX
table.

Foreign exchange transactions are broken down into spot transactions and two general
derivative classifications: forwards and swaps.

Report in the FX table only those transactions that cash settle with the physical exchange of
currency. Do not report non-deliverable transactions (e.g., non-deliverable forwards or
contracts for differences). Transactions reported here should not be excluded from the
calculation of I.O.7: Net 30-day Derivatives Receivables or O.O.20: Net 30-day Derivatives
Payable entries. Report periodic interest payments associated with transactions such as cross-
currency swaps using I.O.1: Derivatives Receivables for contractual unsecured interest


receivable and O.O.1: Derivatives Payables for contractual unsecured interest payable, using
the currency field to identify the currency denomination of each cash flow; do not report
periodic interest payments in the FX table. Additionally, margin collateral flows related to non-
deliverable derivatives should be reported as collateral payable (O.O.2) and collateral
receivable (I.O.2) where appropriate. The exchange of margin collateral related to secured FX
transactions with a physical settlement should also be excluded from this section and reported
as collateral payable (O.O.2) and collateral receivable (I.O.2) where appropriate.

Date and amount fields: The FX table includes “Forward Start” and “Maturity” fields to capture
transactions that have both initial and final settlement cash flows (e.g., FX Swaps). The
“Forward Start” fields generally refer to the “near” leg of the transaction, while the “Maturity”
fields refer to the final maturity or “far” leg of the transaction. An exception is made for the
treatment of FX options, which is described in further detail below.

Currency reporting: FX transactions require the reporting of two currencies (i.e., the receivable
currency and the payable currency). Report the currency receivable upon final maturity (i.e.,
final settlement) of the transaction in the [Currency 1] field, and the currency payable upon
final maturity of the transaction in the [Currency 2] field.

In the case of transactions for Spot FX, FX Forward (i.e., “Forward Outright”) or currency
futures, the one-time settlement is the final maturity.

In the case of FX Swaps, the final maturity refers to the settlement at the long side (or “Far leg”)
of the FX swap transaction.

              The [Maturity Amount Currency 1] field and [Forward Start Amount Currency 1]
                  field must both correspond with the S.FX.[Currency 1] field; therefore the
                  [Forward Start Amount Currency 1] will reflect the payable amount on the near
                  leg of swap transactions, while [Maturity Amount Currency 1] will correspond
                  with the receivable amount upon final maturity (the far leg).

For currencies not currently covered by the FR 2052a report, provide notional amounts
converted into USD and set the [Converted] field equal to “True”.

Centrally settled transactions: Use the [Settlement] field to indicate if transactions are centrally
settled (e.g., through CLS) or bilaterally settled (i.e., OTC). If transactions are centrally settled
through CLS, report “CLS”, if they are centrally settled but not through CLS, report “Other”. If
the transaction is settled bilaterally, report “Bilateral”.

FX Options: Report transactions with embedded options such as currency options, currency
swaptions or other exotic currency products using the product or products that best align with


contractual structure, and indicate the type of option bought or sold in the Foreign Exchange
Option Direction field.

Foreign Exchange Option Directions include “Sold”, which indicates that the reporting entity has
sold the option to its client (i.e., it is exercised at the client’s discretion), and “Purchased”,
which indicates that the reporting entity retains the option (i.e., it is exercised at the reporting
entity’s discretion).

              Report the option expiration date in the [Maturity Bucket] field.

If the option cannot be exercised until a future date, report the first possible date the option
could settle (if exercised) in the [Forward Start Maturity Bucket] field.

For European-style options on forward transactions, where the exercise date coincides with the
expiration date, report the same date using both the [Forward Start Maturity Bucket] and
[Maturity Bucket] fields. For European-style swaptions, report the exercise date using the
[Forward Start Maturity Bucket] field and report the final maturity of the swap using the
[Maturity Bucket] field.

Under circumstances where the reporting entity has sold an option that carries preconditions
or limitations on either the entity’s own or its customer’s ability to exercise the optionality,
report the position ignoring these limitations, unless the option can no longer be contractually
exercised.

              Example: the reporting entity has sold an American-style barrier option to
                  exchange USD for €1mm EUR any time in the next 30 days at $1.34 per euro,
                  provided the spot rate does not exceed $1.40 per euro. Report the option as an
                  option sold with a [Maturity Amount Currency 1] value of €1mm, a [Maturity
                  Amount Currency 2] value of $1.34mm, an [Foreign Exchange Option Direction]
                  of “Sold” and a [Maturity Bucket] of Day 30, even if the existing spot rate is in
                  excess of $1.40 per euro.

Report options with variable pricing for which the rate has yet to be determined using a best
estimate of what the pricing would be at the earliest possible exercise date.

              Example: the reporting entity has purchased an American-style average rate
                  currency option to exchange USD for €1mm EUR based on the average closing
                  price over the two weeks prior to the option being exercised. In this case, use
                  the average closing price over the two weeks prior to the as-of date (T), as the
                  option could be exercised immediately (e.g., if the average rate was $1.34 per
                  euro, report a [Maturity Amount Currency 1] value of €1mm, a [Maturity
                  Amount Currency 2] value of $1.34mm).


For complex transactions that may involve multiple legs and/or resemble a combination of FR
2052a FX Products, disaggregate the transaction and report it as multiple transactions in
accordance with the available FR 2052a FX products and the underlying settlement cash flows.

              Example: A swap contract for which the near leg is non-optional and the far leg is
                  fully optional. Report this transaction as two separate forward FX transactions
                  and use the [Foreign Exchange Option Direction] field to differentiate the
                  optionality on the far leg of the transaction.

The following list outlines the distinct products to be reported in the Supplemental-Foreign
Exchange Table:

### S.FX.1: Spot

Refers to single outright transaction involving the exchange of one currency for another at an
agreed upon rate with immediate delivery according to local market convention (usually two
business days). Report both the receivable and payable sides of the transaction.

### S.FX.2: Forwards and Futures

Refers to transactions involving the physical exchange of two currencies at a rate agreed upon
on the date of the contract for delivery at least two business days in the future or later. Refers
to both forward outright transactions (e.g., bespoke bilateral contracts) and standardized
futures contracts (i.e., exchange traded).

### S.FX.3: Swaps

Refers to transactions involving the exchange of two currencies on a specific date at a rate
agreed at the time of the conclusion of the contract (e.g., the “near” leg), and a reverse
exchange of the same two currencies at a date further in the future at a rate (generally
different from the rate applied to the near leg) agreed at the time of the contract (e.g., the
“far” leg). This product includes but is not limited to both FX forward swaps that involve only
the exchange of notional currency values at the near leg and far leg settlement dates, and
cross-currency swaps that involve both the exchange of notional currency values and periodic
payments of interest over the life of the swap transaction.

Use the “Near” fields (i.e., [Forward Start Amount Currency 1], [Forward Start Amount Currency
2] and [Forward Start Maturity Bucket]) to report the near leg of the transaction, and the
“Maturity Amount” fields (i.e., [Maturity Amount Currency 1], [Maturity Amount Currency 2]
and [Maturity Bucket]) to report the far leg of the transaction.


When reporting transactions for which the near leg has already settled, do not report a value in
the [Forward Start Maturity Bucket] field, but continue to report the original currency
settlement values for the short leg in the “Near Amount” fields.
For swaptions where the final maturity date is dependent on the exercise date (e.g., American-
style or Bermuda-style), indicate the earliest possible exercise date in the [Forward Start
Maturity Bucket] field, and report the final maturity in the [Maturity Bucket] field assuming the
option is exercised at the earliest possible date.

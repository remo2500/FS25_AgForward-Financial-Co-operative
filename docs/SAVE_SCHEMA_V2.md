# AgForward Native Save Schema v2

**File:** `agForwardFinance.xml`  
**Root:** `agForwardFinance`  
**Schema version:** `2`

Schema v2 extends v1 by adding the native liability registry. A v1 save migrates implicitly: if no liability nodes exist, the liability registry loads empty while IDs and ledger entries continue to load normally.

## Root attributes

- `schemaVersion`
- `savedPeriod`
- `savedYear`

## ID counters

`agForwardFinance.idCounters.counter(i)`

Scopes currently expected:

- `TX` — ledger transaction;
- `GRP` — linked transaction group;
- `LIAB` — liability/agreement.

IDs use `AGF-<SCOPE>-<6-digit sequence>`.

## Liability registry

`agForwardFinance.liabilities.liability(i)`

Each liability stores:

- `id`
- `farmId`
- `productType`
- `status`
- optional `displayName`
- `originalPrincipal`
- `principalBalance`
- `creditLimit`
- `accruedInterest`
- `accruedFees`
- `interestRate`
- `termMonths`
- `remainingTermMonths`
- `scheduledPayment`
- `balloonAmount`
- optional start year/period
- optional next-payment year/period
- optional linked `assetId`
- metadata key/value entries

Native revolving products currently recognized by the liability model:

- operating line;
- Crop Input Line of Credit.

For revolving facilities:

`available credit = max(0, credit limit - principal balance)`

Interest and fees are tracked separately from principal and do not currently consume principal-limit availability unless later product policy explicitly changes that rule.

## Ledger

The v1 ledger structure remains valid under v2:

`agForwardFinance.ledger.transactions.transaction(i)`

Funding source and economic purpose remain separate fields. Linked finance/purchase events share a `groupId`.

## Crop Input Line transaction relationship

A financed input purchase validates the CILOC before posting:

1. liability exists;
2. liability belongs to the purchasing farm;
3. liability product is `cropInputLine`;
4. liability is active;
5. requested draw does not exceed available credit;
6. expense category is CILOC-eligible.

Only after the linked ledger batch is successfully posted is the liability principal increased.

Example for a $30,000 fertilizer purchase:

- `creditDraw` +30,000, funding source `cropInputLine`, liability `AGF-LIAB-...`;
- `inputPurchase` -30,000, expense category `fertilizer`, same funding source/liability;
- both entries use the same `AGF-GRP-...` identifier;
- CILOC principal increases by 30,000.

## Migration rules

### v1 -> v2

- retain ID counters;
- retain ledger transactions;
- initialize liability registry empty when no liability nodes exist;
- observed saved IDs continue to advance counters to prevent reuse.

Future schema versions must document explicit migrations from all supported older versions.

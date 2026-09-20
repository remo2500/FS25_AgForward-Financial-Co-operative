# AgForward Origination Close Plan

## Purpose

`AGFOriginationClosePlanService` defines the semantic atomic close that must eventually sit between an accepted server offer and live FS25 mutation.

The service is pure. It does not move cash or create records.

## Financed asset purchase

For a $250,000 equipment purchase with $50,000 cash equity and $200,000 financing, the plan produces:

- new $200,000 equipment-finance liability intent;
- lien/security intent;
- +$200,000 loan-proceeds ledger intent;
- -$250,000 asset-purchase ledger intent;
- expected FS cash delta of -$50,000.

The ledger group therefore reconciles to the actual cash contribution while preserving the full acquisition cost and financing source.

## General term advance

A $100,000 general term loan with no linked purchase produces:

- new $100,000 term liability intent;
- security intent where applicable;
- +$100,000 loan-proceeds ledger intent;
- expected FS cash delta of +$100,000.

## Revolving facility opening

An operating/CILOC facility must open undrawn.

Opening the line:

- creates the liability/facility;
- creates general security where applicable;
- moves no cash;
- posts no draw transaction.

Future utilization is recorded only when an authorized draw occurs.

## Project finance boundary

Project finance is deliberately rejected by this generic close planner.

The project product already supports staged draws. Treating the full approved commitment as day-one principal would overstate debt and cash. Project finance therefore requires a draw-based runtime close/advance path.

## Future runtime atomicity

The eventual server transaction must preflight all effects and either complete or compensate the entire group:

1. validate accepted offer and current state revision;
2. validate authoritative purchase/asset context;
3. validate cash equity;
4. create/activate liability;
5. create security/lien;
6. perform the FS purchase/cash movement;
7. post the linked ledger group;
8. advance the financial state revision;
9. persist successfully.

No product-specific module should independently perform one of these irreversible steps outside the coordinated close boundary.

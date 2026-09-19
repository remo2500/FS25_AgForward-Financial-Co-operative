# AgForward Rate-Term Renewal Plan

## Purpose

A contractual rate term can end before the loan amortization ends. AgForward treats that event as a repricing/re-underwriting amendment of the existing liability, not as a payoff and not as a new loan advance.

`AGFLoanRenewalPlanService` converts a valid renewal quote and credit decision into a pure amendment plan.

## Core rules

- liability identity is preserved;
- existing security/lien identity is preserved;
- renewal itself moves no cash;
- renewal itself posts no loan proceeds;
- remaining amortization is re-scheduled at the renewed rate;
- approval conditions/referrals remain visible in the plan;
- a referred renewal requires explicit manual/server approval;
- a declined renewal cannot produce an amendment plan.

## Principal control

Before the renewal date, the current balance normally differs from the projected renewal balance because scheduled payments have not yet occurred.

At or after the renewal date, a material difference between the actual authoritative principal and the quoted renewal principal requires a re-quote unless the server explicitly authorizes the variance.

This prevents stale renewal calculations after prepayments, missed payments, or other balance changes.

## Runtime boundary

The service never edits a liability. Future runtime promotion must perform the amendment through the same server-authoritative revision/commit infrastructure as other consequential financial changes.

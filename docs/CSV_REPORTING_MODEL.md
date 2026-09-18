# AgForward CSV Reporting Model

## Purpose

`AGFCSVReportService` provides deterministic CSV text from derived AgForward reporting models.

It performs no filesystem writes, so it can be validated before FS25 export paths and permissions are known.

## Current outputs

From a financial-history range it can produce:

1. period summary CSV;
2. expense-category CSV;
3. funding-source CSV.

The period summary includes cash inflows/outflows/net movement, principal, interest, fees, and cash/financed crop-input totals.

## Encoding

Fields containing commas, quotes, carriage returns, or newlines are quoted and embedded quotes are doubled.

Rows use CRLF line endings.

## Runtime gate

Later runtime promotion must choose a safe FS25 export directory and filename policy. CSV generation itself remains independent from filesystem authority.

# AgForward Native UI Action-Bar Model

## Purpose

FS25 presents page actions through native menu-button/action conventions. AgForward should follow that behavior instead of placing oversized custom buttons inside finance panels.

`AGFNativeUIActionModelService` defines the semantic action list before any GIANTS `InputAction` binding is promoted.

## Examples

### Operating line

When selected:

- Draw
- Repay
- Apply

### Crop Input Line

When selected:

- Funding Policy
- Repay
- Apply

Purchase-time CILOC draws remain automatic/preflight-driven and are not represented as a generic manual "finance this input" button.

### Asset finance

When an agreement is selected:

- Details
- View Schedule
- Pay Off

### Payments

For a current account:

- Make Payment
- Pay Off
- View Schedule

For an account with arrears:

- Make Payment
- Cure Account
- Pay Off
- View Schedule

### Reports

- Open Report

## Safety behavior

Read-only actions remain usable in safe mode.

Mutating actions are disabled when:

- AgForward is in read-only safe mode;
- a client is waiting for authoritative synchronization;
- no authoritative server mutation path is available.

The UI model returns a disabled reason so the future frame can explain why an action is unavailable.

## Runtime gate

The service intentionally does not specify actual GIANTS `InputAction` constants.

Those bindings, action glyphs, button ordering, and menu-button callbacks must be verified in the installed FS25 runtime so AgForward uses the same conventions as base-game menu pages.

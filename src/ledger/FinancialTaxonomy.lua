-- AgForward Financial Cooperative
-- Canonical transaction, expense, and funding-source taxonomy.
-- These values are AgForward's internal accounting language and are intentionally
-- independent from Farming Simulator MoneyType statistics.

AGFTransactionType = {
    CREDIT_DRAW = "creditDraw",
    CREDIT_REPAYMENT = "creditRepayment",
    LOAN_PROCEEDS = "loanProceeds",
    LOAN_PAYMENT = "loanPayment",
    PRINCIPAL_PAYMENT = "principalPayment",
    INTEREST_PAYMENT = "interestPayment",
    FINANCE_FEE = "financeFee",
    LATE_FEE = "lateFee",
    INPUT_PURCHASE = "inputPurchase",
    ASSET_PURCHASE = "assetPurchase",
    ASSET_SALE = "assetSale",
    LEASE_RENT = "leaseRent",
    GRANT_RECEIPT = "grantReceipt",
    TAX_PAYMENT = "taxPayment",
    ADJUSTMENT = "adjustment"
}

AGFExpenseCategory = {
    SEED = "seed",
    FERTILIZER = "fertilizer",
    LIME_SOIL_AMENDMENT = "limeSoilAmendment",
    CROP_PROTECTION = "cropProtection",
    FUEL = "fuel",
    LAND_RENT = "landRent",
    INTEREST = "interest",
    FINANCE_FEE = "financeFee",
    LATE_FEE = "lateFee",
    OTHER_INPUT = "otherInput",
    OTHER = "other"
}

AGFFundingSource = {
    CASH = "cash",
    OPERATING_LINE = "operatingLine",
    CROP_INPUT_LINE = "cropInputLine",
    TERM_LOAN = "termLoan",
    EQUIPMENT_FINANCE = "equipmentFinance",
    PROJECT_FINANCE = "projectFinance",
    LAND_FINANCE = "landFinance",
    GRANT = "grant",
    OTHER = "other"
}

AGFProductType = {
    OPERATING_LINE = "operatingLine",
    CROP_INPUT_LINE = "cropInputLine",
    TERM_LOAN = "termLoan",
    EQUIPMENT_FINANCE = "equipmentFinance",
    PROJECT_FINANCE = "projectFinance",
    LAND_FINANCE = "landFinance",
    LAND_LEASE = "landLease"
}

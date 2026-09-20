from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime_log = load_module("agf_runtime_log", ROOT / "tools" / "analyze_runtime_log.py")
save_validator = load_module("agf_save_validator", ROOT / "tools" / "validate_agforward_save.py")


class RuntimeLogTests(unittest.TestCase):
    def test_clean_initialization(self):
        report = runtime_log.analyze(
            "AgForward: no existing financial state; starting a new AgForward save\n"
            "AgForward: initialized (Red Tape: NOT_INSTALLED, save: NEW_STATE)\n"
        )
        self.assertEqual(report["status"], "PASS_FIRST_PASS")
        self.assertEqual(report["counts"]["initialization_lines"], 1)
        self.assertEqual(report["counts"]["lua_error_markers"], 0)

    def test_duplicate_initialization_fails(self):
        report = runtime_log.analyze(
            "AgForward: initialized once\n"
            "AgForward: initialized twice\n"
        )
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(any("initialized 2 times" in item for item in report["critical_findings"]))

    def test_lua_error_fails(self):
        report = runtime_log.analyze(
            "AgForward: initialized\n"
            "Error: Running LUA method 'update'.\n"
            "attempt to index a nil value\n"
        )
        self.assertEqual(report["status"], "FAIL")
        self.assertGreaterEqual(report["counts"]["lua_error_markers"], 1)


class SaveValidatorTests(unittest.TestCase):
    VALID_XML = """<?xml version='1.0' encoding='utf-8'?>
<agForwardFinance schemaVersion="3" saveGeneration="5" savedYear="2026" savedPeriod="9">
  <idCounters>
    <counter scope="TX" value="2" />
    <counter scope="GRP" value="1" />
    <counter scope="LIAB" value="1" />
  </idCounters>
  <liabilities>
    <liability id="AGF-LIAB-000001" farmId="1" productType="cropInputLine" status="active"
      originalPrincipal="0" principalBalance="30000" creditLimit="100000"
      accruedInterest="0" accruedFees="0" interestRate="0.07"
      termMonths="0" remainingTermMonths="0" scheduledPayment="0" balloonAmount="0" />
  </liabilities>
  <ledger>
    <transactions>
      <transaction id="AGF-TX-000001" farmId="1" type="creditDraw" amount="30000"
        principal="0" interest="0" fees="0" groupId="AGF-GRP-000001"
        fundingSource="cropInputLine" liabilityId="AGF-LIAB-000001" />
      <transaction id="AGF-TX-000002" farmId="1" type="inputPurchase" amount="-30000"
        principal="0" interest="0" fees="0" groupId="AGF-GRP-000001"
        expenseCategory="fertilizer" fundingSource="cropInputLine" liabilityId="AGF-LIAB-000001" />
    </transactions>
  </ledger>
  <settlement engineVersion="1" lastCompletedKey="" />
</agForwardFinance>
"""

    def validate_text(self, text: str):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "agForwardFinance.xml"
            path.write_text(text, encoding="utf-8")
            return save_validator.validate(path)

    def test_valid_schema_v3(self):
        report = self.validate_text(self.VALID_XML)
        self.assertTrue(report["valid"], report["errors"])
        self.assertEqual(report["schemaVersion"], 3)
        self.assertEqual(report["saveGeneration"], 5)
        self.assertEqual(report["counts"]["transactions"], 2)
        self.assertEqual(report["counts"]["liabilities"], 1)

    def test_broken_ciloc_group_fails(self):
        report = self.validate_text(self.VALID_XML.replace('amount="-30000"', 'amount="-29000"'))
        self.assertFalse(report["valid"])
        self.assertTrue(any("does not reconcile to zero" in item for item in report["errors"]))

    def test_unresolved_liability_fails(self):
        report = self.validate_text(self.VALID_XML.replace("AGF-LIAB-000001\" />", "AGF-LIAB-000999\" />", 1))
        self.assertFalse(report["valid"])
        self.assertTrue(any("unresolved liabilityId" in item for item in report["errors"]))

    def test_counter_reuse_risk_fails(self):
        report = self.validate_text(self.VALID_XML.replace('scope="TX" value="2"', 'scope="TX" value="1"'))
        self.assertFalse(report["valid"])
        self.assertTrue(any("ID counter TX=1 is below observed maximum 2" in item for item in report["errors"]))

    def test_newer_schema_warns(self):
        report = self.validate_text(self.VALID_XML.replace('schemaVersion="3"', 'schemaVersion="4"'))
        self.assertTrue(report["valid"])
        self.assertTrue(any("newer than validator schema" in item for item in report["warnings"]))


if __name__ == "__main__":
    unittest.main()

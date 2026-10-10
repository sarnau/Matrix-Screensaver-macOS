#!/bin/bash
# Runs the unit tests and prints a one-line summary. Usage: Scripts/test.sh [TestClass]
cd "$(dirname "$0")/.."
ONLY=(); [ -n "${1:-}" ] && ONLY=(-only-testing:MatrixRainTests/$1)
rm -rf build/result.xcresult
xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData -quiet -resultBundlePath build/result.xcresult "${ONLY[@]}" > build/test.log 2>&1
RC=$?
grep -E "error:|warning:" build/test.log | grep -v -E "IDETestOperations|appintentsmetadataprocessor" | sort -u | head -20
xcrun xcresulttool get test-results summary --path build/result.xcresult 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("result=%s passed=%s failed=%s total=%s"%(d["result"],d["passedTests"],d["failedTests"],d["totalTestCount"])); [print("FAIL:",f.get("testName"),f.get("failureText")) for f in d.get("testFailures",[])]'
exit $RC

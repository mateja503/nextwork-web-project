#!/bin/bash
# ============================================================================
# run-tests.sh  -  PRE-BUILD VALIDATION CHECKS
#
# Called by buildspec.yml during the build phase, BEFORE "mvn compile".
#
# What these are:     structural checks. They confirm the project layout is
#                     intact and the files the pipeline depends on exist.
# What these are NOT: real unit tests. Nothing here tests application
#                     behaviour. (JUnit is declared in pom.xml but unused.)
#
# Why run before compiling: these take under a second, a Maven compile takes
# much longer. If the structure is broken there is no point paying for the
# compile. This is "fail fast".
#
# THE EXIT CODE IS THE WHOLE POINT:
#   exit 0  = success, CodeBuild carries on to compile and package
#   exit 1  = failure, CodeBuild stops immediately and the pipeline fails,
#             so nothing broken ever reaches the deploy stage
# ============================================================================

# The shebang above tells the OS to run this file with bash.

echo "==== RUNNING SIMPLE TESTS ===="

# --- Test 1: does the source directory exist? -------------------------------
# Catches a badly broken checkout or an accidental deletion of the whole tree.
echo "Test 1: Checking project structure..."
# -d tests "exists AND is a directory"
if [ -d "src" ]; then
  echo "✅ PASS: src directory exists"
else
  echo "❌ FAIL: src directory not found"
  # Non-zero exit kills the build here and now. Nothing further runs.
  exit 1
fi

# --- Test 2: does the actual application file exist? ------------------------
# This is the most useful check in the file. index.jsp IS the application - if
# it is missing, the build would still "succeed" and produce an empty .war that
# deploys cleanly and serves a 404. Catching it here prevents a silent failure.
echo "Test 2: Checking for web app files..."
# -f tests "exists AND is a regular file"
if [ -f "src/main/webapp/index.jsp" ]; then
  echo "✅ PASS: index.jsp exists"
else
  echo "❌ FAIL: index.jsp not found"
  exit 1
fi

# --- Test 3: placeholder ----------------------------------------------------
# Does nothing useful. It exists to confirm the test harness itself is wired up
# and reaching the end of the script. Safe to replace with a real check.
echo "Test 3: Simple validation test..."
echo "✅ PASS: This test always passes"

echo "==== ALL TESTS PASSED ===="

# Exit 0 explicitly = "everything passed". CodeBuild reads this and proceeds to
# the compile step. Without an explicit exit the script would return the status
# of the last command, which is less predictable.
exit 0

#!/bin/bash
# ============================================================================
# stop_server.sh  -  CODEDEPLOY HOOK: ApplicationStop
#
# RUNS FIRST in the deployment lifecycle:
#   1. ApplicationStop    <- YOU ARE HERE
#   2. BeforeInstall      install_dependencies.sh
#   3. Install            CodeDeploy copies the .war
#   4. ApplicationStart   start_server.sh
#
# Why stop the services before deploying: the new .war overwrites the old one
# in Tomcat's webapps folder, and you cannot reliably overwrite a file Tomcat
# currently holds open.
#
# ---------------------------------------------------------------------------
# THE BIG GOTCHA - worth remembering
#
# CodeDeploy runs this hook from the PREVIOUSLY DEPLOYED revision, not the one
# being deployed right now. So if you ever push a BROKEN version of this file,
# it gets stuck: every later deployment keeps running the broken copy already
# sitting on the instance, and pushing a fix does not help, because the fix
# cannot be installed until the broken stop script succeeds first.
# Recovering means fixing the file by hand on the instance.
#
# This is exactly what commit 8b10901 demonstrated on purpose, by replacing
# this script with a misspelled "systemctll" plus "exit 1" to force a failed
# deployment and confirm the automatic rollback worked. Commit 21f1a5e put it
# back to the working version you see below.
# ============================================================================

# --- Stop Apache httpd (the public facing web server on port 80) ------------

# pgrep searches the running process list for a process named "httpd" and
# prints its process ID. If httpd is not running it prints nothing.
# The result is captured into a variable.
isExistApp="$(pgrep httpd)"

# -n tests "is this string NON-empty", i.e. "did pgrep actually find something".
#
# WHY BOTHER CHECKING FIRST: calling systemctl stop on a service that is
# already stopped can return a non-zero exit code. A non-zero exit from any
# CodeDeploy hook FAILS THE ENTIRE DEPLOYMENT. So this guard exists to make the
# script safe to run whether or not the service happens to be up - which
# matters on a first-ever deployment to a fresh instance, where neither service
# is running yet.
if [[ -n $isExistApp ]]; then
sudo systemctl stop httpd.service
fi

# --- Stop Tomcat (the Java servlet container on port 8080) ------------------
# Identical pattern to the block above.
isExistApp="$(pgrep tomcat)"
if [[ -n $isExistApp ]]; then
sudo systemctl stop tomcat.service
fi

# Note: there is no explicit "exit 0" here. The script ends with whatever the
# last command returned, which in normal operation is success. Both stops are
# guarded, so the common failure modes are already handled.

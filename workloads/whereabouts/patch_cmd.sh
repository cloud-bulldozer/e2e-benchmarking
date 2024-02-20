#!/usr/bin/env bash
oc patch network.operator.openshift.io cluster --patch-file=reconciler.yml --type=merge

#!/bin/bash
# usage: run.sh [template_db=a1db]  -> clones the built canonical DB into a1s and runs the audit scenarios s0..s5 in ONE psql session.
# Needs: scratch PG16 on /tmp:5544 and a DB built with tests/sql/final_build.sh (default name a1db). Expected numbers in each file are hand-computed BEFORE the run.
T=${1:-a1db}; cd "$(dirname "$0")"; E=../../e2e
psql -h /tmp -p 5544 -U postgres -q -c "drop database if exists a1s" -c "create database a1s template $T" 2>&1 | grep -v NOTICE
cat $E/00_common.sql s0_setup.sql s1_recipe.sql s2_pool.sql s3_multistage.sql s4_price.sql s5_reports.sql s6_layers.sql > /tmp/a1_run.sql
psql -h /tmp -p 5544 -U postgres -d a1s -v mode=def -qAt -f /tmp/a1_run.sql 2>&1

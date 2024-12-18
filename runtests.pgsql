\unset ECHO
\set QUIET 1
-- Turn off echo and keep things quiet.

-- Format the output for nice TAP.
\pset format unaligned
\pset tuples_only true
\pset pager off

-- Revert all changes on failure.
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

-- Load the TAP functions.
BEGIN;
\i pgtap.sql

-- Plan the tests.
SELECT plan(1);

-- Run the tests.
SELECT * FROM runtests();

-- Finish the tests and clean up.
SELECT * FROM finish();
ROLLBACK;
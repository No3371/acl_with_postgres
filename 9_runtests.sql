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

SET search_path = acl, pgtap;

-- Load the TAP functions.
BEGIN;
-- \i pgtap.sql

-- Plan the tests.
-- SELECT plan(6);

-- Run the tests.
SELECT * FROM runtests('acl'::name, '^pgtap_test');

-- Finish the tests and clean up.
SELECT * FROM finish();
ROLLBACK;
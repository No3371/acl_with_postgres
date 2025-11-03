SET search_path = acl, pgtap;

-- Load the TAP functions.
BEGIN;
SELECT * FROM runtests('acl'::name, '^pgtap_test');
ROLLBACK;
-- RAISE EXCEPTION 'Quick failing the init'; -- for fast docker test run
SET search_path = acl, pgtap;

-- Load the TAP functions.
BEGIN;
SELECT * FROM runtests('acl'::name, '^pgtap_test');
ROLLBACK;
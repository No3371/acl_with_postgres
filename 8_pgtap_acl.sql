SET search_path = acl;

CREATE OR REPLACE FUNCTION pgtap_test_acl_test (
) RETURNS SETOF TEXT AS $$
BEGIN
    RETURN NEXT is( MAX(user_id), NULL, 'Should have no users') FROM "user";
END; $$ LANGUAGE plpgsql; 

CREATE OR REPLACE FUNCTION pgtap_test_find_parent_perm_id(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO "user" (user_id) VALUES (1);
    INSERT INTO "role" (role_name, priority) VALUES ('market_owner', 100), ('moderator', 50), ('default', 0);
    INSERT INTO perm (permission) VALUES ('market'), ('market/create'), ('market/modify'), ('market/delete'), ('market/event');
    INSERT INTO perm (permission)
    VALUES ('market/asset'),
           ('market/asset/create'),
           ('market/asset/modify'),
           ('market/asset/delete'),
           ('market/asset/event');
    INSERT INTO perm (permission) VALUES ('market/trade');
    INSERT INTO perm (permission) VALUES ('user_privilege');
    
    RETURN NEXT is( (SELECT find_parent_perm_id('market/create'))      , (SELECT get_perm_id('market')), 'market -> market/create');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/modify'))      , (SELECT get_perm_id('market')), 'market -> market/modify');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/delete'))      , (SELECT get_perm_id('market')), 'market -> market/delete');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/event'))       , (SELECT get_perm_id('market')), 'market -> market/event');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset'))       , (SELECT get_perm_id('market')), 'market -> market/asset');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset/create')), (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/create');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset/modify')), (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/modify');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset/delete')), (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/delete');
    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset/event')) , (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/event');

    -- Should throw an exception for updating perm
    RETURN NEXT throws_ok('UPDATE perm SET permission = ''market/exchange'' WHERE permission = ''market/trade''');

    DELETE FROM perm WHERE permission = 'market/asset';

    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset/event')) , NULL, 'NULL (Deleted) -> market/asset/event');

    INSERT INTO perm (permission) VALUES ('market/asset');

    RETURN NEXT is( (SELECT find_parent_perm_id('market/asset/event')) , (SELECT get_perm_id('market/asset')), 'market/asset (Re-inserted) -> market/asset/event');

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgtap_test_find_perm_ancestors(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO perm (permission)
    VALUES ('market'),
           ('market/asset'),
           ('market/asset/create'),
           ('market/asset/modify'),
           ('market/asset/delete'),
           ('market/asset/event');
    
    -- At this point, the perm_tree and perm_ancestors tables should be populated
    RETURN NEXT is ((SELECT COUNT(*) FROM perm_upstream), 6::BIGINT, 'Should have 6 rows in perm_upstream');

    RETURN NEXT is ((SELECT perm_id FROM find_perm_ancestors_inclusive((SELECT get_perm_id('market'))) LIMIT 1), (SELECT get_perm_id('market')), 'market''s upstream should have only itself');
    RETURN NEXT is ((SELECT perm_id FROM find_perm_ancestors_inclusive((SELECT get_perm_id('market/asset'))) ORDER BY depth ASC OFFSET 1 LIMIT 1), (SELECT get_perm_id('market')), 'market/asset should have market as ancestor');
    RETURN NEXT is ((SELECT perm_id FROM find_perm_ancestors_inclusive((SELECT get_perm_id('market/asset/create'))) ORDER BY depth ASC OFFSET 1 LIMIT 1), (SELECT get_perm_id('market/asset')), 'market/asset/create should have market/asset as ancestor');
    RETURN NEXT is ((SELECT perm_id FROM find_perm_ancestors_inclusive((SELECT get_perm_id('market/asset/modify'))) ORDER BY depth ASC OFFSET 2 LIMIT 1), (SELECT get_perm_id('market')), 'market/asset/create should have market as grand ancestor');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgtap_test_find_perm_descendants(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO perm (permission)
    VALUES ('market'),
           ('market/asset'),
           ('market/asset/create'),
           ('market/asset/modify');
    
    -- At this point, the perm_tree and perm_ancestors tables should be populated
    RETURN NEXT is ((SELECT COUNT(*) FROM perm_downstream), 4::BIGINT, 'Should have 4 rows in perm_downstream');

    RETURN NEXT is (
        (SELECT perm_id FROM find_perm_descendants_inclusive((SELECT get_perm_id('market'))) ORDER BY depth ASC LIMIT 1),
        (SELECT get_perm_id('market')),
        'market''s first downstream should be itself'
    );
    RETURN NEXT is (
        (SELECT perm_id FROM find_perm_descendants_inclusive((SELECT get_perm_id('market'))) WHERE depth = 1),
        (SELECT perm_id FROM perm WHERE permission = 'market/asset'),
        'market''s first next downstream should be market/asset'
    );
    RETURN NEXT is (
        (SELECT COUNT(*) FROM find_perm_descendants_inclusive((SELECT get_perm_id('market/asset')))),
        3::BIGINT,
        'market/asset should have 3 downstream including itself'
    );
    RETURN NEXT is (
        (SELECT perm_id FROM find_perm_descendants_inclusive((SELECT get_perm_id('market/asset/create')))),
        (SELECT get_perm_id('market/asset/create')),
        'market/asset/create''s only downstream should be itself'
    );
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION pgtap_test_acl_perm_tree(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO perm (permission)
    VALUES ('market'),
           ('market/asset'),
           ('market/asset/create'),
           ('market/asset/modify'),
           ('market/asset/delete'),
           ('market/asset/event');
    
    -- At this point, the perm_tree and perm_ancestors tables should be populated
    RETURN NEXT is ((SELECT COUNT(*) FROM perm_tree), 6::BIGINT, 'Should have 6 perm_tree rows');

    RETURN NEXT is ((SELECT parent_perm_id FROM perm_tree WHERE perm_id = (SELECT get_perm_id('market'))), NULL, 'market should have no parent');
    RETURN NEXT is ((SELECT parent_perm_id FROM perm_tree WHERE perm_id = (SELECT get_perm_id('market/asset'))), (SELECT get_perm_id('market')), 'market/asset should have market as parent');
    RETURN NEXT is ((SELECT parent_perm_id FROM perm_tree WHERE perm_id = (SELECT get_perm_id('market/asset/create'))), (SELECT get_perm_id('market/asset')), 'market/asset/create should have market/asset as parent');
    RETURN NEXT is ((SELECT parent_perm_id FROM perm_tree WHERE perm_id = (SELECT get_perm_id('market/asset/modify'))), (SELECT get_perm_id('market/asset')), 'market/asset/modify should have market/asset as parent');
    RETURN NEXT is ((SELECT parent_perm_id FROM perm_tree WHERE perm_id = (SELECT get_perm_id('market/asset/delete'))), (SELECT get_perm_id('market/asset')), 'market/asset/delete should have market/asset as parent');
    RETURN NEXT is ((SELECT parent_perm_id FROM perm_tree WHERE perm_id = (SELECT get_perm_id('market/asset/event'))), (SELECT get_perm_id('market/asset')), 'market/asset/event should have market/asset as parent');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgtap_test_acl_perm_value(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO "user" (user_id) VALUES (1);
    INSERT INTO "role" (role_name, priority) VALUES ('market_owner', 100), ('moderator', 50), ('default', 0);
    INSERT INTO perm (permission) VALUES ('market'), ('market/create'), ('market/modify'), ('market/delete'), ('market/event');
    INSERT INTO perm (permission) VALUES ('market/asset'), ('market/asset/create'), ('market/asset/modify'), ('market/asset/delete'), ('market/asset/event');
    INSERT INTO perm (permission) VALUES ('market/trade');
    INSERT INTO perm (permission) VALUES ('user_privilege');
    INSERT INTO perm (permission) VALUES ('null_perm');

    INSERT INTO role_perm (role_id, perm_id, scope, state) VALUES
        ((SELECT get_role_id('market_owner')), (SELECT get_perm_id('market')), 0, true);

    INSERT INTO user_role (user_id, role_id) VALUES (1, (SELECT get_role_id('market_owner')));
    
    INSERT INTO user_perm (user_id, perm_id, scope, state) VALUES
        (1, (SELECT get_perm_id('user_privilege')), 0, true),
        (1, (SELECT get_perm_id('market/modify')), 0, false);
    
    RETURN NEXT is((SELECT check_permission(1, 0, 'market/create')), true, 'market -> market/create');
    RETURN NEXT is((SELECT check_permission(1, 0, 'market/modify')), false, 'market/modify: false (user)');
    RETURN NEXT is((SELECT check_permission(1, 0, 'market/delete')), true, 'market -> market/delete');
    RETURN NEXT is((SELECT check_permission(1, 0, 'user_privilege')), true, 'user_privilege');
    RETURN NEXT is((SELECT check_permission(1, 0, 'null_perm')), NULL, 'null_perm: NULL (not assigned)');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgtap_test_acl_perm_value_scoped(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO "user" (user_id) VALUES (1);
    INSERT INTO "role" (role_name, priority) VALUES ('market_owner', 100), ('moderator', 50), ('default', 0);
    INSERT INTO perm (permission) VALUES ('market'), ('market/create'), ('market/modify'), ('market/delete'), ('market/event');

    INSERT INTO role_perm (role_id, perm_id, scope, state) VALUES
        ((SELECT get_role_id('market_owner')), (SELECT get_perm_id('market')), 0, true);

    INSERT INTO user_role (user_id, role_id) VALUES (1, (SELECT get_role_id('market_owner')));
    
    INSERT INTO user_perm (user_id, perm_id, scope, state) VALUES
        (1, (SELECT get_perm_id('market/modify')), 0, false);
    
    RETURN NEXT is((SELECT check_permission(1, 0, 'market/create')), true, 'market -> market/create');
    RETURN NEXT is((SELECT check_permission(1, 1, 'market/create')), NULL, 'market -> market/create (should be NULL because of wrong scope)');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgtap_test_acl_cache(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO "user" (user_id) VALUES (1);
    INSERT INTO "role" (role_name, priority) VALUES ('market_owner', 100), ('moderator', 50), ('default', 0);
    INSERT INTO perm (permission) VALUES ('market'), ('market/create'), ('market/modify'), ('market/delete'), ('market/event');
    INSERT INTO perm (permission) VALUES ('market/asset'), ('market/asset/create'), ('market/asset/modify'), ('market/asset/delete'), ('market/asset/event');
    INSERT INTO perm (permission) VALUES ('market/trade');
    INSERT INTO perm (permission) VALUES ('user_privilege');

    INSERT INTO role_perm (role_id, perm_id, scope, state) VALUES
        ((SELECT get_role_id('market_owner')), (SELECT get_perm_id('market')), 0, true);

    INSERT INTO user_role (user_id, role_id) VALUES (1, (SELECT get_role_id('market_owner')));
    
    INSERT INTO user_perm (user_id, perm_id, scope, state) VALUES
        (1, (SELECT get_perm_id('user_privilege')), 0, true),
        (1, (SELECT get_perm_id('market/modify')), 0, false);
    
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/create')), true, 'market -> market/create');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/modify')), false, 'market/modify: false (user)');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/delete')), true, 'market -> market/delete');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/trade')), true, 'market/trade: true (role)');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'user_privilege')), true, 'user_privilege');

    INSERT INTO role_perm (role_id, perm_id, scope, state) VALUES
        ((SELECT get_role_id('market_owner')), (SELECT get_perm_id('market/trade')), 0, false);

    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/trade')), false, 'market/trade: false (role / specified false)');

    RETURN NEXT is((SELECT COUNT(*) FROM perm_cache), 5::BIGINT, 'Should have cached 5 perms');

    DELETE FROM role_perm
    WHERE role_id = (SELECT get_role_id('market_owner'))
      AND perm_id = (SELECT get_perm_id('market/trade'));

    RETURN NEXT is((SELECT COUNT(*) FROM perm_cache), 4::BIGINT, 'Should have cleared 1 cache');
    
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/create')), true, 'market -> market/create');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/modify')), false, 'market/modify: false (user)');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/delete')), true, 'market -> market/delete');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/trade')), true, 'market/trade: true (role / false revoked)');
    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'user_privilege')), true, 'user_privilege');
    
    RETURN NEXT is((SELECT COUNT(*) FROM perm_cache), 5::BIGINT, 'Should have cached 5 perms');

    DELETE FROM user_role WHERE user_id = 1;

    RETURN NEXT is((SELECT COUNT(*) FROM perm_cache), 1::BIGINT, 'Should have cleared all cache except user_privilege');

    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/create')), NULL, 'market/create: NULL (role removed)');

    INSERT INTO user_role (user_id, role_id) VALUES (1, (SELECT get_role_id('market_owner')));

    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/create')), true, 'market/create: true (role re-added and cache is up-to-date)');
    
    RETURN NEXT is((SELECT COUNT(*) FROM perm_cache), 2::BIGINT, 'Should have cached 1 perm');

    UPDATE perm_cache SET "state" = false;

    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/create')), false, 'market/create: false (cache overridden)');

    UPDATE perm_cache SET cached_at = now() - '1 day'::interval;

    RETURN NEXT is((SELECT check_perm_cached(1, 0, 'market/create')), true, 'market/create: true (outdated and recached)');
END;
$$ LANGUAGE plpgsql;
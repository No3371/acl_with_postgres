CREATE OR REPLACE FUNCTION pgtap_test_acl_test (
) RETURNS SETOF TEXT AS $$
BEGIN
    RETURN NEXT is( MAX(user_id), NULL, 'Should have no users') FROM "user";
END; $$ LANGUAGE plpgsql; 

CREATE OR REPLACE FUNCTION pgtap_test_acl_perm_tree(
) RETURNS SETOF TEXT AS $$
BEGIN
    INSERT INTO "user" (user_id) VALUES (1);
    INSERT INTO "role" (role_name, priority) VALUES ('market_owner', 100), ('moderator', 50), ('default', 0);
    INSERT INTO perm (permission) VALUES ('market'), ('market/create'), ('market/modify'), ('market/delete'), ('market/event');
    INSERT INTO perm (permission) VALUES ('market/asset'), ('market/asset/create'), ('market/asset/modify'), ('market/asset/delete'), ('market/asset/event');
    INSERT INTO perm (permission) VALUES ('market/trade');
    INSERT INTO perm (permission) VALUES ('user_privilege');
    
    RETURN NEXT is( (SELECT find_parent_permission('market/create'))      , (SELECT get_perm_id('market')), 'market -> market/create');
    RETURN NEXT is( (SELECT find_parent_permission('market/modify'))      , (SELECT get_perm_id('market')), 'market -> market/modify');
    RETURN NEXT is( (SELECT find_parent_permission('market/delete'))      , (SELECT get_perm_id('market')), 'market -> market/delete');
    RETURN NEXT is( (SELECT find_parent_permission('market/event'))       , (SELECT get_perm_id('market')), 'market -> market/event');
    RETURN NEXT is( (SELECT find_parent_permission('market/asset'))       , (SELECT get_perm_id('market')), 'market -> market/asset');
    RETURN NEXT is( (SELECT find_parent_permission('market/asset/create')), (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/create');
    RETURN NEXT is( (SELECT find_parent_permission('market/asset/modify')), (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/modify');
    RETURN NEXT is( (SELECT find_parent_permission('market/asset/delete')), (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/delete');
    RETURN NEXT is( (SELECT find_parent_permission('market/asset/event')) , (SELECT get_perm_id('market/asset')), 'market/asset -> market/asset/event');

    RETURN NEXT throws_ok('UPDATE perm SET permission = ''market/exchange'' WHERE permission = ''market/trade''');

    DELETE FROM perm WHERE permission = 'market/asset';

    RETURN NEXT is( (SELECT find_parent_permission('market/asset/event')) , NULL, 'NULL (Deleted) -> market/asset/event');

    INSERT INTO perm (permission) VALUES ('market/asset');

    RETURN NEXT is( (SELECT find_parent_permission('market/asset/event')) , (SELECT get_perm_id('market/asset')), 'market/asset (Re-inserted) -> market/asset/event');

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

    INSERT INTO role_perm (role_id, perm_id, scope, state) VALUES
        ((SELECT get_role_id('market_owner')), (SELECT get_perm_id('market')), 0, true);

    INSERT INTO user_role (user_id, role_id) VALUES (1, (SELECT get_role_id('market_owner')));
    
    INSERT INTO user_perm (user_id, perm_id, scope, state) VALUES
        (1, (SELECT get_perm_id('user_privilege')), 0, true),
        (1, (SELECT get_perm_id('market/modify')), 0, false);
    
    RETURN NEXT is((SELECT check_permission(1, 'market/create', 0)), true, 'market -> market/create');
    RETURN NEXT is((SELECT check_permission(1, 'market/modify', 0)), false, 'market/modify: false (user)');
    RETURN NEXT is((SELECT check_permission(1, 'market/delete', 0)), true, 'market -> market/delete');
    RETURN NEXT is((SELECT check_permission(1, 'user_privilege', 0)), true, 'user_privilege');
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
    
    RETURN NEXT is((SELECT check_permission_cached(1, 'market/create', 0)), true, 'market -> market/create');
    RETURN NEXT is((SELECT check_permission_cached(1, 'market/modify', 0)), false, 'market/modify: false (user)');
    RETURN NEXT is((SELECT check_permission_cached(1, 'market/delete', 0)), true, 'market -> market/delete');
    RETURN NEXT is((SELECT check_permission_cached(1, 'user_privilege', 0)), true, 'user_privilege');

    RETURN NEXT is((SELECT COUNT(*) FROM permission_cache), 4::BIGINT, 'Should have cached 4 perms');

    DELETE FROM user_role WHERE user_id = 1;

    RETURN NEXT is((SELECT COUNT(*) FROM permission_cache), 0::BIGINT, 'Should have cleared cache');
    RETURN NEXT is((SELECT check_permission_cached(1, 'market/create', 0)), false, 'market/create: false (role removed)');

    INSERT INTO user_role (user_id, role_id) VALUES (1, (SELECT get_role_id('market_owner')));

    RETURN NEXT is((SELECT check_permission_cached(1, 'market/create', 0)), true, 'market/create: true (re-cache)');
    
    RETURN NEXT is((SELECT COUNT(*) FROM permission_cache), 1::BIGINT, 'Should have cached 1 perm');

    UPDATE permission_cache SET state = false;

    RETURN NEXT is((SELECT check_permission_cached(1, 'market/create', 0)), false, 'market/create: false (modified cache)');

    UPDATE permission_cache SET cached_at = now() - '1 day'::interval;

    RETURN NEXT is((SELECT check_permission_cached(1, 'market/create', 0)), true, 'market/create: true (outdated and recached)');
END;
$$ LANGUAGE plpgsql;
-- Insert test data
INSERT INTO "user" DEFAULT VALUES;
INSERT INTO "perm" (permission, default_state) VALUES 
    ('message', false),
    ('message/create', false),
    ('message/delete', false),
    ('privilege', false);
    
INSERT INTO "role" (role_name, priority) VALUES 
    ('admin', 100),
    ('member', 0);
    
-- Get the IDs
DO $$ 
DECLARE
    v_user_id BIGINT;
    v_admin_role_id BIGINT;
    v_member_role_id BIGINT;
    v_create_perm_id BIGINT;
    v_delete_perm_id BIGINT;
    v_privilege_perm_id BIGINT;
BEGIN
    SELECT user_id INTO v_user_id FROM "user" LIMIT 1;
    SELECT role_id INTO v_admin_role_id FROM role WHERE role_name = 'admin';
    SELECT role_id INTO v_member_role_id FROM role WHERE role_name = 'member';
    SELECT perm_id INTO v_create_perm_id FROM perm WHERE permission = 'message/create';
    SELECT perm_id INTO v_delete_perm_id FROM perm WHERE permission = 'message/delete';
    SELECT perm_id INTO v_privilege_perm_id FROM perm WHERE permission = 'privilege';
    
    -- Assign user to member role
    INSERT INTO user_role (user_id, role_id) VALUES (v_user_id, v_member_role_id);
    
    -- Set role permissions
    INSERT INTO role_perm (role_id, perm_id, state, scope) VALUES
        (v_member_role_id, v_delete_perm_id, false, 0),  -- member can't delete
        (v_member_role_id, v_create_perm_id, true, 0);   -- But can create
        
    -- Set direct user permission
    INSERT INTO user_perm (user_id, perm_id, state, scope) VALUES
        (v_user_id, v_privilege_perm_id, true, 0);       -- User can delete regardless of role
END $$;

-- Test the permissions
SELECT check_permission(1, 'message', 0) as message_perm,
       check_permission(1, 'message/create', 0) as create_perm,
       check_permission(1, 'message/delete', 0) as delete_perm,
       check_permission(1, 'privilege', 0) as privilege;


-- Clear existing data
TRUNCATE perm CASCADE;

INSERT INTO "role" (role_name) VALUES ('test_role');

INSERT INTO "user" DEFAULT VALUES;
    
-- Insert test permissions
INSERT INTO perm (permission, default_state) VALUES 
    ('manage', false),
    ('manage/users', false),
    ('manage/content', true);

SELECT * FROM user;
SELECT * FROM role;
SELECT * FROM perm;

-- View created partitions
SELECT tablename 
FROM pg_tables 
WHERE tablename LIKE 'role_perm_p%' 
   OR tablename LIKE 'user_perm_p%'
ORDER BY tablename;

-- Test inserting data into partitions
INSERT INTO role_perm (role_id, perm_id, scope, state)
SELECT 1, perm_id, 1, true
FROM perm
WHERE permission = 'manage';

INSERT INTO user_perm (user_id, perm_id, scope, state)
SELECT 1, perm_id, 1, true
FROM perm
WHERE permission = 'manage/users';

-- View data in partitions
SELECT 'role_perm' as table_name, rp.*, p.permission
FROM role_perm rp
JOIN perm p ON p.perm_id = rp.perm_id;

SELECT 'user_perm' as table_name, up.*, p.permission
FROM user_perm up
JOIN perm p ON p.perm_id = up.perm_id;

-- Test updating a permission
UPDATE perm 
SET permission = 'manage/users/create'
WHERE permission = 'manage/users';

SELECT * FROM perm;

-- View partitions after update
SELECT tablename 
FROM pg_tables 
WHERE tablename LIKE 'role_perm_p%' 
   OR tablename LIKE 'user_perm_p%'
ORDER BY tablename;

-- Test deleting a permission
DELETE FROM perm WHERE permission = 'manage/content';

-- View final partition list
SELECT tablename 
FROM pg_tables 
WHERE tablename LIKE 'role_perm_p%' 
   OR tablename LIKE 'user_perm_p%'
ORDER BY tablename;

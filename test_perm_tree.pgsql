-- Clear existing data
TRUNCATE perm CASCADE;

-- Test data for permission tree
INSERT INTO perm (permission, default_state) VALUES 
    ('manage', false),
    ('manage/users', false),
    ('manage/users/create', true),
    ('manage/users/delete', false),
    ('manage/content', false),
    ('manage/content/edit', true);

-- View the initial tree structure
SELECT 
    p.permission,
    parent.permission as parent_permission
FROM perm_tree pt
JOIN perm p ON p.perm_id = pt.perm_id
LEFT JOIN perm parent ON parent.perm_id = pt.parent_perm_id
ORDER BY p.permission;

-- Test updating a permission
UPDATE perm 
SET permission = 'manage/users/modify'
WHERE permission = 'manage/users/create';

-- View the updated tree
SELECT 
    p.permission,
    parent.permission as parent_permission
FROM perm_tree pt
JOIN perm p ON p.perm_id = pt.perm_id
LEFT JOIN perm parent ON parent.perm_id = pt.parent_perm_id
ORDER BY p.permission;

-- Test deleting a permission
DELETE FROM perm WHERE permission = 'manage/content/edit';

-- View the final tree
SELECT 
    p.permission,
    parent.permission as parent_permission
FROM perm_tree pt
JOIN perm p ON p.perm_id = pt.perm_id
LEFT JOIN perm parent ON parent.perm_id = pt.parent_perm_id
ORDER BY p.permission;

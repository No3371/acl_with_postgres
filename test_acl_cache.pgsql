-- Clear existing data
TRUNCATE perm CASCADE;
TRUNCATE permission_cache;

-- Insert test data
INSERT INTO perm (permission, default_state) VALUES 
    ('manage', false),
    ('manage/users', false),
    ('manage/users/create', true);

INSERT INTO "user" (user_id) VALUES (1);
INSERT INTO role (role_id, role_name, priority) VALUES (1, 'admin', 100);
INSERT INTO user_role (user_id, role_id) VALUES (1, 1);

-- Insert some permissions
INSERT INTO role_perm (role_id, perm_id, scope, state) 
SELECT 1, perm_id, 1, true
FROM perm 
WHERE permission = 'manage';

-- Test initial permission check (should create cache entry)
SELECT 'Initial Check' as test,
       check_permission(1, 'manage', 1) as result;

-- View cache contents
SELECT 'Cache After Initial Check' as test,
       user_id, permission, scope, result, cached_at
FROM permission_cache;

-- Test cached permission check (should use cache)
SELECT 'Cached Check' as test,
       check_permission(1, 'manage', 1) as result;

-- Modify role permission (should clear cache for user)
UPDATE role_perm 
SET state = false 
WHERE role_id = 1 AND perm_id = (SELECT perm_id FROM perm WHERE permission = 'manage');

-- View cache after modification
SELECT 'Cache After Permission Update' as test,
       user_id, permission, scope, result, cached_at
FROM permission_cache;

-- Check permission again (should create new cache entry)
SELECT 'Check After Cache Clear' as test,
       check_permission(1, 'manage', 1) as result;

-- Test cache expiration
-- Note: In real testing, you'd wait an hour or temporarily modify the expiration check
-- For demonstration, we'll manually expire a cache entry
UPDATE permission_cache 
SET cached_at = NOW() - INTERVAL '2 hours';

-- Check permission (should create new cache entry due to expiration)
SELECT 'Check After Cache Expiration' as test,
       check_permission(1, 'manage', 1) as result;

-- View final cache state
SELECT 'Final Cache State' as test,
       user_id, permission, scope, result, cached_at
FROM permission_cache;

-- Test perm_tree change clearing all cache
INSERT INTO perm (permission, default_state) VALUES ('manage/reports', true);

-- View cache after perm_tree change
SELECT 'Cache After Perm Tree Change' as test,
       user_id, permission, scope, result, cached_at
FROM permission_cache;

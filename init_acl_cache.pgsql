DROP TABLE IF EXISTS "permission_cache";
-- Create unlogged cache table
CREATE UNLOGGED TABLE "permission_cache" (
    user_id BIGINT NOT NULL,
    permission TEXT NOT NULL,
    scope BIGINT NOT NULL,
    state BOOLEAN NOT NULL,
    cached_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, permission, scope)
) PARTITION BY LIST (permission);

-- Create default partition
CREATE TABLE permission_cache_default PARTITION OF permission_cache DEFAULT;

-- Function to create partition for a permission
CREATE OR REPLACE FUNCTION create_permission_cache_partition(p_permission TEXT)
RETURNS VOID AS $$
DECLARE
    v_partition_name TEXT;
BEGIN
    -- Generate safe partition name (replace '/' with '_')
    v_partition_name := 'permission_cache_p' || replace(p_permission, '/', '_');
    
    -- Create partition if it doesn't exist
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I PARTITION OF permission_cache 
        FOR VALUES IN (%L)', 
        v_partition_name, p_permission
    );
END;
$$ LANGUAGE plpgsql;

-- Function to drop partition for a permission
CREATE OR REPLACE FUNCTION drop_permission_cache_partition(p_permission TEXT)
RETURNS VOID AS $$
DECLARE
    v_partition_name TEXT;
BEGIN
    -- Generate partition name
    v_partition_name := 'permission_cache_p' || replace(p_permission, '/', '_');
    
    -- Drop partition if it exists
    EXECUTE format('DROP TABLE IF EXISTS %I', v_partition_name);
END;
$$ LANGUAGE plpgsql;

-- Function to manage cache partitions on perm changes
CREATE OR REPLACE FUNCTION manage_permission_cache_partitions()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        PERFORM create_permission_cache_partition(NEW.permission);
    ELSIF (TG_OP = 'UPDATE') THEN
        -- For updates, drop old partition and create new one
        PERFORM drop_permission_cache_partition(OLD.permission);
        PERFORM create_permission_cache_partition(NEW.permission);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM drop_permission_cache_partition(OLD.permission);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for partition management
DROP TRIGGER IF EXISTS manage_cache_partitions_trigger ON perm;
CREATE TRIGGER manage_cache_partitions_trigger
    AFTER INSERT OR UPDATE OR DELETE ON perm
    FOR EACH ROW
    EXECUTE FUNCTION manage_permission_cache_partitions();

-- Function to create initial partitions for existing permissions
CREATE OR REPLACE FUNCTION create_initial_cache_partitions()
RETURNS VOID AS $$
DECLARE
    v_permission TEXT;
BEGIN
    FOR v_permission IN SELECT permission FROM perm LOOP
        PERFORM create_permission_cache_partition(v_permission);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create initial partitions for existing permissions
SELECT create_initial_cache_partitions();

-- Function to clear expired cache entries
CREATE OR REPLACE FUNCTION clear_expired_cache() RETURNS VOID AS $$
BEGIN
    DELETE FROM permission_cache 
    WHERE cached_at < NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Function to clear cache for specific user
CREATE OR REPLACE FUNCTION clear_user_permission_cache(p_user_id BIGINT) 
RETURNS VOID AS $$
BEGIN
    DELETE FROM permission_cache WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to clear cache for users with specific role
CREATE OR REPLACE FUNCTION clear_role_permission_cache(p_role_id BIGINT) 
RETURNS VOID AS $$
BEGIN
    DELETE FROM permission_cache 
    WHERE user_id IN (
        SELECT user_id 
        FROM user_role 
        WHERE role_id = p_role_id
    );
END;
$$ LANGUAGE plpgsql;

-- Trigger function for user_perm changes
CREATE OR REPLACE FUNCTION trigger_clear_user_perm_cache()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM clear_user_permission_cache(OLD.user_id);
    ELSE
        PERFORM clear_user_permission_cache(NEW.user_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for role_perm changes
CREATE OR REPLACE FUNCTION trigger_clear_role_perm_cache()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM clear_role_permission_cache(OLD.role_id);
    ELSE
        PERFORM clear_role_permission_cache(NEW.role_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for user_role changes
CREATE OR REPLACE FUNCTION trigger_clear_user_role_cache()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM clear_user_permission_cache(OLD.user_id);
    ELSE
        PERFORM clear_user_permission_cache(NEW.user_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for perm_tree changes
CREATE OR REPLACE FUNCTION trigger_clear_all_permission_cache()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM permission_cache;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS clear_user_perm_cache ON user_perm;
CREATE TRIGGER clear_user_perm_cache
    AFTER INSERT OR UPDATE OR DELETE ON user_perm
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_user_perm_cache();

DROP TRIGGER IF EXISTS clear_role_perm_cache ON role_perm;
CREATE TRIGGER clear_role_perm_cache
    AFTER INSERT OR UPDATE OR DELETE ON role_perm
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_role_perm_cache();

DROP TRIGGER IF EXISTS clear_user_role_cache ON user_role;
CREATE TRIGGER clear_user_role_cache
    AFTER INSERT OR UPDATE OR DELETE ON user_role
    FOR EACH ROW
    EXECUTE FUNCTION trigger_clear_user_role_cache();

DROP TRIGGER IF EXISTS clear_all_permission_cache ON perm_tree;
CREATE TRIGGER clear_all_permission_cache
    AFTER INSERT OR UPDATE OR DELETE ON perm_tree
    FOR EACH STATEMENT
    EXECUTE FUNCTION trigger_clear_all_permission_cache();

CREATE OR REPLACE FUNCTION check_permission_cached(
    p_user_id BIGINT,
    p_permission TEXT,
    p_scope BIGINT
) RETURNS BOOLEAN AS $$
DECLARE
    v_state BOOLEAN;
    v_cached_state BOOLEAN;
    v_perm_parts TEXT[];
    v_partial_perm TEXT;
    i INTEGER;
BEGIN    
    -- Check cache first
    SELECT state INTO v_cached_state
    FROM permission_cache
    WHERE user_id = p_user_id
      AND permission = p_permission
      AND scope = p_scope
      AND cached_at > NOW() - INTERVAL '1 hour';
      
    IF v_cached_state IS NOT NULL THEN
        RETURN v_cached_state;
    END IF;

    SELECT check_permission($1, $2, $3) INTO v_state;
    
    -- Cache and return final state
    INSERT INTO permission_cache (user_id, permission, scope, state)
    VALUES (p_user_id, p_permission, p_scope, v_state)
    ON CONFLICT (user_id, permission, scope) DO UPDATE SET state = v_state,
                              cached_at = NOW();
    
    RETURN v_state;
END;
$$ LANGUAGE plpgsql;

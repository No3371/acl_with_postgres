-- Function to create partition for a permission
CREATE OR REPLACE FUNCTION create_permission_partitions(p_perm_id BIGINT)
RETURNS VOID AS $$
DECLARE
    v_role_perm_partition TEXT;
    v_user_perm_partition TEXT;
BEGIN
    -- Generate partition names
    v_role_perm_partition := format('role_perm_p%s', p_perm_id);
    v_user_perm_partition := format('user_perm_p%s', p_perm_id);
    
    -- Create role_perm partition
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I PARTITION OF role_perm 
        FOR VALUES IN (%s)', 
        v_role_perm_partition, p_perm_id
    );
    
    -- Create user_perm partition
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I PARTITION OF user_perm 
        FOR VALUES IN (%s)', 
        v_user_perm_partition, p_perm_id
    );
    
    -- Add foreign key constraints to partitions
    EXECUTE format('
        ALTER TABLE %I 
        ADD CONSTRAINT %I FOREIGN KEY (role_id) 
        REFERENCES role(role_id) ON DELETE RESTRICT', 
        v_role_perm_partition, 
        format('%s_role_fk', v_role_perm_partition)
    );
    
    EXECUTE format('
        ALTER TABLE %I 
        ADD CONSTRAINT %I FOREIGN KEY (perm_id) 
        REFERENCES perm(perm_id) ON DELETE RESTRICT', 
        v_role_perm_partition, 
        format('%s_perm_fk', v_role_perm_partition)
    );
    
    EXECUTE format('
        ALTER TABLE %I 
        ADD CONSTRAINT %I FOREIGN KEY (user_id) 
        REFERENCES "user"(user_id) ON DELETE RESTRICT', 
        v_user_perm_partition, 
        format('%s_user_fk', v_user_perm_partition)
    );
    
    EXECUTE format('
        ALTER TABLE %I 
        ADD CONSTRAINT %I FOREIGN KEY (perm_id) 
        REFERENCES perm(perm_id) ON DELETE RESTRICT', 
        v_user_perm_partition, 
        format('%s_perm_fk', v_user_perm_partition)
    );
END;
$$ LANGUAGE plpgsql;

-- Function to drop partition for a permission
CREATE OR REPLACE FUNCTION drop_permission_partitions(p_perm_id BIGINT)
RETURNS VOID AS $$
DECLARE
    v_role_perm_partition TEXT;
    v_user_perm_partition TEXT;
BEGIN
    -- Generate partition names
    v_role_perm_partition := format('role_perm_p%s', p_perm_id);
    v_user_perm_partition := format('user_perm_p%s', p_perm_id);
    
    -- Drop partitions if they exist
    EXECUTE format('DROP TABLE IF EXISTS %I', v_role_perm_partition);
    EXECUTE format('DROP TABLE IF EXISTS %I', v_user_perm_partition);
END;
$$ LANGUAGE plpgsql;

-- Function to manage partitions on perm changes
CREATE OR REPLACE FUNCTION manage_permission_partitions()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        PERFORM create_permission_partitions(NEW.perm_id);
    ELSIF (TG_OP = 'UPDATE') THEN
        -- For updates, drop and recreate the partition
        PERFORM drop_permission_partitions(NEW.perm_id);
        PERFORM create_permission_partitions(NEW.perm_id);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM drop_permission_partitions(OLD.perm_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for partition management
DROP TRIGGER IF EXISTS manage_partitions_trigger ON perm;
CREATE TRIGGER manage_partitions_trigger
    AFTER INSERT OR UPDATE OR DELETE ON perm
    FOR EACH ROW
    EXECUTE FUNCTION manage_permission_partitions();

-- Function to create initial partitions for existing permissions
CREATE OR REPLACE FUNCTION create_initial_partitions()
RETURNS VOID AS $$
DECLARE
    v_perm_id BIGINT;
BEGIN
    FOR v_perm_id IN SELECT perm_id FROM perm LOOP
        PERFORM create_permission_partitions(v_perm_id);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create initial partitions for existing permissions
SELECT create_initial_partitions();

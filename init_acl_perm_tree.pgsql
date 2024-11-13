DROP TABLE IF EXISTS "perm_tree";
CREATE TABLE "perm_tree" (
    perm_id BIGINT PRIMARY KEY,
    parent_perm_id BIGINT, CHECK (parent_perm_id is distinct from perm_id)
);
-- Foreign keys are not required because the whole table gets rebuilt on perm change

-- Function to find parent permission ID
CREATE OR REPLACE FUNCTION find_parent_permission(p_permission TEXT) 
RETURNS BIGINT AS $$
DECLARE
    v_parent_id BIGINT;
    v_last_slash INTEGER;
BEGIN
    -- Find the last slash in the permission string
    v_last_slash := strpos(reverse(p_permission), '/');
    
    -- If no slash found, there's no parent
    IF v_last_slash = 0 THEN
        RETURN NULL;
    END IF;
    
    -- Get the parent permission string (everything before the last slash)
    SELECT perm_id INTO v_parent_id
    FROM perm
    WHERE permission = substring(p_permission, 1, length(p_permission) - v_last_slash)
    ORDER BY length(permission) DESC
    LIMIT 1;
    
    RETURN v_parent_id;
END;
$$ LANGUAGE plpgsql;

-- Function to rebuild the entire permission tree
CREATE OR REPLACE FUNCTION rebuild_perm_tree() 
RETURNS VOID AS $$
BEGIN
    -- Clear the existing tree
    DELETE FROM perm_tree;
    
    -- Rebuild the tree for all permissions
    INSERT INTO perm_tree (perm_id, parent_perm_id)
    SELECT 
        p.perm_id,
        find_parent_permission(p.permission)
    FROM perm p;
END;
$$ LANGUAGE plpgsql;

-- Trigger function that calls rebuild_perm_tree
CREATE OR REPLACE FUNCTION trigger_rebuild_perm_tree()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM rebuild_perm_tree();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS rebuild_perm_tree_trigger ON perm;
CREATE TRIGGER rebuild_perm_tree_trigger
    AFTER INSERT OR DELETE ON perm
    FOR EACH STATEMENT
    EXECUTE FUNCTION trigger_rebuild_perm_tree();


CREATE OR REPLACE FUNCTION prevent_perm_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Permissions are suppoesd to be immutable to prevent hierachy corruption. Delete and Insert instead.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_perm_update_trigger
    BEFORE UPDATE ON perm
    FOR EACH ROW
    EXECUTE FUNCTION prevent_perm_update();

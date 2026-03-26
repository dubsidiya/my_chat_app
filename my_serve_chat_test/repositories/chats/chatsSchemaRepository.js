export const hasChatUsersFolderColumn = async (db) => {
  return db.query(
    `
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chat_users'
      AND column_name = 'folder'
    LIMIT 1
    `
  );
};

export const hasChatUsersFolderIdColumn = async (db) => {
  return db.query(
    `
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chat_users'
      AND column_name = 'folder_id'
    LIMIT 1
    `
  );
};

export const hasChatFoldersTable = async (db) => {
  return db.query(
    `
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'chat_folders'
    LIMIT 1
    `
  );
};

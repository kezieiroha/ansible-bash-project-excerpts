#!/bin/bash
# PostgreSQL Book Database Setup Script  
# Author: Kezie Iroha v1 Initial Script

export DB_NAME="$1"
export ADMIN_USER="$2"
export VIEW_USER="$3"
 
DATE=$(date +%F_%T)
export LOGFILE=/tmp/Database_Build_${DATE}.log
exec > >(tee -a "$LOGFILE") 2>&1

# RegEx identifiers 
export RGX_IDENTIFIER='^[a-zA-Z0-9_]+$'

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <db_name> <admin_user> <view_user>"
  exit 1
fi

command -v psql >/dev/null 2>&1 || export PATH=$PATH:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin
if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql not found in PATH. Please ensure PostgreSQL client tools are installed."
  exit 1
fi

if [[ ! "$DB_NAME" =~ $RGX_IDENTIFIER ]]; then
  echo "Invalid database name: $DB_NAME"
  echo "Database Name must contain only letters, numbers, or underscores (no spaces, dashes, punctuation)."
  exit 1
fi

if [[ ! "$ADMIN_USER" =~ $RGX_IDENTIFIER ]]; then
  echo "Invalid admin username: $ADMIN_USER"
  echo "Usernames must contain only letters, numbers, or underscores."
  exit 1
fi

if [[ ! "$VIEW_USER" =~ $RGX_IDENTIFIER ]]; then
  echo "Invalid view username: $VIEW_USER"
  echo "Usernames must contain only letters, numbers, or underscores."
  exit 1
fi

echo "Setting up PostgreSQL book database..."

read -s -r -p "Enter password for admin user: " ADMIN_PASS
echo
read -s -r -p "Enter password for view user: " VIEW_PASS
echo

if [[ -z "$ADMIN_PASS" || ${#ADMIN_PASS} -lt 6 ]]; then
    echo "Admin password must be at least 6 characters."
    exit 1
fi

if [[ -z "$VIEW_PASS" || ${#VIEW_PASS} -lt 6 ]]; then
    echo "Viewer password must be at least 6 characters."
    exit 1
fi

if psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    echo "Database ${DB_NAME} already exists."
else
    echo "Creating database ${DB_NAME}..."
    psql -U postgres -c "CREATE DATABASE ${DB_NAME};"
fi

if psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${ADMIN_USER}'" | grep -q 1; then
    echo "Admin user ${ADMIN_USER} already exists."
else
    echo "Creating Admin user ${ADMIN_USER}..."
    psql -U postgres -c "CREATE USER ${ADMIN_USER} WITH PASSWORD '${ADMIN_PASS}';"
fi

if psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${VIEW_USER}'" | grep -q 1; then
    echo "View user ${VIEW_USER} already exists."
else
    echo "Creating View user ${VIEW_USER}..."
    psql -U postgres -c "CREATE USER ${VIEW_USER} WITH PASSWORD '${VIEW_PASS}';"
fi

psql -U postgres -d ${DB_NAME} << EOF

CREATE SCHEMA IF NOT EXISTS ${ADMIN_USER} AUTHORIZATION ${ADMIN_USER};
SET search_path TO ${ADMIN_USER};

CREATE TABLE IF NOT EXISTS publishers (
    publisher_id SERIAL PRIMARY KEY,
    publisher_name VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS authors (
    author_id SERIAL PRIMARY KEY,
    author_name VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    subtitle VARCHAR(255),
    author_id INTEGER NOT NULL REFERENCES authors(author_id),
    publisher_id INTEGER NOT NULL REFERENCES publishers(publisher_id)
);

CREATE INDEX IF NOT EXISTS idx_books_author_id ON books(author_id);
CREATE INDEX IF NOT EXISTS idx_books_publisher_id ON books(publisher_id);

CREATE OR REPLACE PROCEDURE insert_book_fn(
    p_title TEXT,
    p_subtitle TEXT,
    p_author_id INTEGER,
    p_publisher_id INTEGER
)
LANGUAGE plpgsql AS \$\$
BEGIN
    INSERT INTO books (title, subtitle, author_id, publisher_id)
    VALUES (p_title, p_subtitle, p_author_id, p_publisher_id);
END;
\$\$;

CREATE OR REPLACE VIEW admin_books_vw AS
SELECT 
    b.book_id,
    b.title,
    b.subtitle,
    a.author_name,
    p.publisher_name
FROM 
    books b, authors a, publishers p
WHERE 
    b.author_id = a.author_id
AND b.publisher_id = p.publisher_id;

GRANT CONNECT, TEMP ON DATABASE ${DB_NAME} TO ${ADMIN_USER};
GRANT USAGE ON SCHEMA ${ADMIN_USER} TO ${ADMIN_USER}, ${VIEW_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${ADMIN_USER} TO ${ADMIN_USER};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ${ADMIN_USER} TO ${ADMIN_USER};

GRANT CONNECT ON DATABASE ${DB_NAME} TO ${VIEW_USER};
GRANT SELECT ON ${ADMIN_USER}.admin_books_vw TO ${VIEW_USER};

EOF

echo "Database: ${DB_NAME} setup completed successfully!"
echo "Admin user: ${ADMIN_USER}"
echo "View user: ${VIEW_USER}"
echo "Log file: ${LOGFILE}"

exit 0

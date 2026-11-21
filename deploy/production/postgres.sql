-- Run once as the postgres superuser on the existing PostgreSQL 16.
-- Creates a separate role and database; the store app's databases and
-- roles are not touched, and the mafia role cannot see them.
CREATE ROLE mafia LOGIN PASSWORD 'CHANGE_ME' CONNECTION LIMIT 20;
CREATE DATABASE mafia OWNER mafia;
REVOKE ALL ON DATABASE mafia FROM PUBLIC;

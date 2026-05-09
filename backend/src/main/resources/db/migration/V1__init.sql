-- Baseline migration. The /api/me endpoint reads everything it needs from
-- the JWT claims, so the backend doesn't persist users in v1. Future
-- migrations can add tables here.
SELECT 1;

#!/bin/bash
# save as assess-current-state.sh

echo "=== CURRENT STATE ASSESSMENT ==="

# Check current volume usage
echo "1. Current Docker volumes:"
docker volume ls

echo "2. Volume sizes:"
docker system df -v

echo "3. Bind mount directories and sizes:"
echo "Supabase volumes:"
du -sh ./supabase/volumes/* 2>/dev/null || echo "No supabase volumes found"

echo "Neo4j directories:"
du -sh ./neo4j/* 2>/dev/null || echo "No neo4j directories found"

echo "N8N backup:"
du -sh ./n8n/backup 2>/dev/null || echo "No n8n backup found"

echo "Flowise home:"
du -sh ~/.flowise 2>/dev/null || echo "No flowise home found"

echo "4. Currently running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Mounts}}"

echo "5. Services using bind mounts:"
docker compose config | grep -B2 -A1 "\./"

echo "=== ASSESSMENT COMPLETE ==="

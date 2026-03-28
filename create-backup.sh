#!/bin/bash
# save as create-backup.sh

BACKUP_DIR="./docker-migration-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup in $BACKUP_DIR"

# Backup bind mount data
echo "Backing up Supabase data..."
cp -r ./supabase/volumes "$BACKUP_DIR/supabase-volumes" 2>/dev/null || echo "No supabase volumes to backup"

echo "Backing up Neo4j data..."
cp -r ./neo4j "$BACKUP_DIR/neo4j" 2>/dev/null || echo "No neo4j data to backup"

echo "Backing up N8N data..."
cp -r ./n8n "$BACKUP_DIR/n8n" 2>/dev/null || echo "No n8n data to backup"

echo "Backing up Flowise data..."
cp -r ~/.flowise "$BACKUP_DIR/flowise-home" 2>/dev/null || echo "No flowise data to backup"

# Backup configuration files
echo "Backing up configuration..."
cp docker-compose.yml "$BACKUP_DIR/"
cp supabase/docker/docker-compose.yml "$BACKUP_DIR/supabase-docker-compose.yml"
cp .env "$BACKUP_DIR/.env.backup" 2>/dev/null || echo "No .env file"
cp supabase/.env "$BACKUP_DIR/supabase.env.backup" 2>/dev/null || echo "No supabase .env file"

# Export current volumes to tarballs
echo "Exporting named volumes..."
for volume in $(docker volume ls --format "{{.Name}}" | grep -E "(n8n_storage|ollama_storage|flowise|caddy-data|caddy-config|valkey-data|langfuse_|portainer_data)"); do
    echo "Exporting volume: $volume"
    docker run --rm -v "$volume:/data" -v "$PWD/$BACKUP_DIR:/backup" alpine tar czf "/backup/volume-$volume.tar.gz" -C /data .
done

echo "Backup completed in $BACKUP_DIR"
echo "Backup size: $(du -sh $BACKUP_DIR)"

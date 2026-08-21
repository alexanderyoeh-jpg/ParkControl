#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE DESPLIEGUE Y ACTUALIZACIÓN AUTOMÁTICA DE PARKCONTROL EN VPS (Ubuntu/Debian)
# ==============================================================================
set -euo pipefail

echo "======================================================"
echo "🚀 INICIANDO DESPLIEGUE DE PARKCONTROL EN PRODUCCIÓN"
echo "======================================================"

APP_DIR="/var/www/parkcontrol"
DB_DIR="/var/lib/parkcontrol"
BACKUPS_DIR="/var/backups/parkcontrol"

# 1. Crear directorios con permisos seguros
echo "📁 Preparando directorios del sistema..."
sudo mkdir -p "$APP_DIR" "$DB_DIR" "$BACKUPS_DIR"
sudo chown -R www-data:www-data "$DB_DIR" "$BACKUPS_DIR"
sudo chmod 700 "$DB_DIR" "$BACKUPS_DIR"

# 2. Instalar dependencias del backend
echo "📦 Instalando dependencias de Node.js..."
cd "$APP_DIR/backend"
npm ci --only=production

# 3. Ejecutar preflight y pruebas de verificación
echo "🔍 Ejecutando preflight de producción..."
npm run check
npm run test:config
npm run test:preflight

# 4. Compilar Flutter Web si está presente
if [ -d "$APP_DIR/frontend" ]; then
    echo "🌐 Compilando Flutter Web..."
    cd "$APP_DIR/frontend"
    flutter build web --release --pwa-strategy=none
fi

# 5. Configurar o recargar PM2
echo "⚡ Recargando servicio backend con PM2..."
cd "$APP_DIR/backend"
if pm2 describe parkcontrol-backend > /dev/null 2>&1; then
    pm2 reload ecosystem.config.js --env production
else
    pm2 start ecosystem.config.js --env production
    pm2 save
fi

# 6. Configurar respaldo automático en cron si no existe
CRON_JOB="0 * * * * cd $APP_DIR/backend && node scripts/respaldo_sqlite.js >> /var/log/parkcontrol_backups.log 2>&1"
(crontab -l 2>/dev/null | grep -F "respaldo_sqlite.js") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "======================================================"
echo "✅ DESPLIEGUE COMPLETADO EXITOSAMENTE"
echo "API activa en: https://api.parkcontrol.cl"
echo "App Web activa en: https://app.parkcontrol.cl"
echo "======================================================"

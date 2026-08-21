module.exports = {
  apps: [
    {
      name: 'parkcontrol-backend',
      script: './server.js',
      cwd: '/var/www/parkcontrol/backend',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        PARKCONTROL_HOST: '127.0.0.1',
        PARKCONTROL_DB_PATH: '/var/lib/parkcontrol/parkcontrol.db',
        PARKCONTROL_ALLOW_SETUP: 'true',
        PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
        PARKCONTROL_ALLOWED_ORIGINS: 'https://app.neatspace.cl,https://admin.neatspace.cl,https://neatspace.cl,https://www.neatspace.cl',
        PARKCONTROL_PUBLIC_URL: 'https://api.neatspace.cl',
        PARKCONTROL_LOGIN_MAX_ATTEMPTS: '5',
        PARKCONTROL_LOGIN_WINDOW_MS: '900000',
        PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado'
      },
      env_production: {
        NODE_ENV: 'production',
        PORT: 3000,
        PARKCONTROL_HOST: '127.0.0.1',
        PARKCONTROL_DB_PATH: '/var/lib/parkcontrol/parkcontrol.db',
        PARKCONTROL_ALLOW_SETUP: 'true',
        PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
        PARKCONTROL_ALLOWED_ORIGINS: 'https://app.neatspace.cl,https://admin.neatspace.cl,https://neatspace.cl,https://www.neatspace.cl',
        PARKCONTROL_PUBLIC_URL: 'https://api.neatspace.cl',
        PARKCONTROL_LOGIN_MAX_ATTEMPTS: '5',
        PARKCONTROL_LOGIN_WINDOW_MS: '900000',
        PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado'
      }
    }
  ]
};

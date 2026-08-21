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
      env_production: {
        NODE_ENV: 'production',
        PORT: 3000,
        PARKCONTROL_HOST: '127.0.0.1',
        PARKCONTROL_DB_PATH: '/var/lib/parkcontrol/parkcontrol.db',
        PARKCONTROL_ALLOW_SETUP: 'true',
        PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
        PARKCONTROL_ALLOWED_ORIGINS: 'https://app.neatsapce.cl,https://admin.neatsapce.cl,https://neatsapce.cl',
        PARKCONTROL_PUBLIC_URL: 'https://api.neatsapce.cl',
        PARKCONTROL_LOGIN_MAX_ATTEMPTS: '5',
        PARKCONTROL_LOGIN_WINDOW_MS: '900000',
        PARKCONTROL_EMAIL_PROVIDER: 'resend',
        PARKCONTROL_RESEND_API_KEY: 're_TU_CLAVE_AQUI',
        PARKCONTROL_EMAIL_FROM: 'alertas@parkcontrol.cl',
        PARKCONTROL_EMAIL_REPLY_TO: 'soporte@parkcontrol.cl',
        PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN: 'APP_USR-TU_ACCESS_TOKEN',
        PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET: 'TU_WEBHOOK_SECRET'
      }
    }
  ]
};

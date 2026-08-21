# Arquitectura oficial del SuperAdministrador de ParkControl

## Objetivo

El SuperAdministrador es la cuenta propietaria de ParkControl. Administra la cartera completa de estacionamientos, mientras cada cliente conserva su propio administrador, cajeros y datos operativos aislados.

La arquitectura objetivo queda dividida en tres áreas:

1. **Gestión comercial y suscripciones:** crear clientes, asignar plan Lite o Pro, registrar pagos manuales, controlar vencimientos y activar, suspender o reactivar cuentas.
2. **Gestión operativa global:** consultar cada estacionamiento y, cuando sea necesario, entrar mediante un modo de soporte temporal, identificado y auditado.
3. **Gestión técnica y soporte:** diagnóstico, incidencias, auditoría, registros técnicos, respaldos, recuperación y supervisión del servicio online.

## Jerarquía

```text
ParkControl SaaS
└── SuperAdministrador global (propietario)
    ├── Estacionamiento A — Plan Lite
    │   └── Administrador
    │       └── Cajeros
    ├── Estacionamiento B — Plan Pro
    │   └── Administrador
    │       └── Cajeros
    └── Estacionamiento C — Plan Pro
        └── Administrador
            └── Cajeros
```

Cada consulta operativa obtiene el estacionamiento desde la sesión autenticada. Un cliente nunca puede elegir el identificador de otro cliente ni consultar sus movimientos, usuarios, boletas, tarifas o reportes.

## Funciones terminadas en el MVP local

- Configuración inicial única de la cuenta propietaria, protegida por un código de un solo uso.
- Dashboard con clientes activos, suspendidos, vencidos, por vencer e ingresos de suscripciones del mes.
- Creación y edición de estacionamientos con planes Lite y Pro.
- Creación de un administrador inicial y administradores adicionales.
- Suspensión y reactivación inmediata, incluyendo el bloqueo de sesiones abiertas.
- Registro manual de pagos por transferencia o efectivo.
- Anulación lógica de pagos con motivo, auditoría y restauración segura del estado comercial anterior cuando corresponde.
- Historial de pagos y auditoría global.
- Cambio de contraseña de la cuenta propietaria y restablecimiento de administradores.
- Aislamiento multicliente de usuarios, tarifas, vehículos, movimientos, historial, boletas, contabilidad y auditoría.

## Acceso operativo global: regla de seguridad

La futura opción **Entrar al estacionamiento** no usará la contraseña del cliente ni una suplantación invisible. Se implementará como **modo soporte** con estas reglas:

- motivo obligatorio;
- autorización temporal y de corta duración;
- estacionamiento objetivo fijado por el servidor;
- aviso visible de “Modo soporte ParkControl”;
- registro de inicio, acciones y finalización en auditoría global;
- salida explícita para volver al panel propietario;
- ningún dato de un cliente puede quedar disponible al cambiar a otro.

Hasta que este diseño esté implementado y probado, el SuperAdministrador administra comercialmente al cliente, pero no opera silenciosamente dentro de su cuenta.

## Capa técnica pendiente de producción

Diagnóstico remoto, registros centralizados, monitoreo, respaldos automáticos y recuperación pertenecen a la infraestructura online. Se implementarán junto con PostgreSQL administrado, HTTPS, control de origen, secretos de producción y pruebas reales de restauración.

Un respaldo no se considerará terminado solo por existir: deberá tener retención definida, acceso restringido y una restauración comprobada.

## Planes

Los nombres comerciales oficiales son **Lite** y **Pro**. En esta etapa se pueden asignar y cambiar manualmente. Antes del piloto se definirá una matriz explícita de límites y funciones de cada plan; hasta entonces el plan no debe bloquear funciones operativas de forma silenciosa.

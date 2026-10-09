# Documentación de Sulotec

Documentación técnica del ecosistema Sulotec: qué hay, dónde está, cómo se conecta y cómo se opera.

| # | Documento | Para qué sirve |
|---|---|---|
| 1 | [Proyecto Sulotec](01-proyecto-sulotec.md) | Visión general: productos, aplicaciones, repositorios, cuentas, reglas y pendientes |
| 2 | [Oracle Cloud](02-oracle-cloud.md) | La infraestructura: servidor, discos, buckets, respaldos, usuarios, Terraform y operación diaria |
| 3 | [Cloudflare](03-cloudflare.md) | Dominio, HTTPS, túnel, rutas, Zero Trust y Access (quién puede entrar a qué) |
| 4 | [Integración de proyectos](04-integracion-de-proyectos.md) | Cómo se unen las piezas: identidad, publicación, datos, y cómo sumar un producto nuevo |

**Documentos relacionados**

| Documento | Para qué sirve |
|---|---|
| [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md) | Controles del Anexo A y brechas pendientes |
| [`CONTEXTO-PARA-OTRO-CHAT.md`](../CONTEXTO-PARA-OTRO-CHAT.md) | Bitácora detallada de decisiones |
| [`apps/portal/README.md`](../apps/portal/README.md) | sulotec.com |
| [`apps/cuenta/README.md`](../apps/cuenta/README.md) | Cuentas (Keycloak) |
| [`apps/buscador/README.md`](../apps/buscador/README.md) | Operación del Buscador |
| [Sulotec/buscador-interno](https://github.com/Sulotec/buscador-interno) | Código del Buscador |

**Reglas de la documentación**

- Aquí **nunca** van contraseñas, tokens ni datos personales de clientes. Los secretos viven solo en el servidor (`/opt/sulotec/*.env`) y en el gestor de contraseñas de la empresa.
- Si cambias algo en la infraestructura, actualiza el documento correspondiente en el mismo commit.

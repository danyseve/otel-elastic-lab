# Observabilidad *vendor-neutral* con OpenTelemetry y Elastic Cloud on Kubernetes en alta disponibilidad, on-premise y con licencia gratuita

**Autor:** danyseve · **Versión:** 0.2 (borrador) · **Repositorio:** `github.com/danyseve/otel-elastic-lab`

---

## Resumen

Este trabajo describe el diseño, la implementación y la validación experimental de una plataforma de
observabilidad completa (trazas, métricas y logs) construida con estándares abiertos y desplegada
on-premise. La telemetría se genera y transporta con **OpenTelemetry**, mediante colectores
gestionados por el *OpenTelemetry Operator*, y se almacena en **Elasticsearch** desplegado con
**Elastic Cloud on Kubernetes (ECK)** sobre un clúster **k3s** de tres nodos en alta disponibilidad.
Cada nodo es una máquina virtual KVM en un host físico distinto. Toda la plataforma utiliza
exclusivamente la **licencia gratuita (Basic)** de Elastic, se define como código (Terraform,
Ansible y Helmfile) y se valida mediante experimentos de fallo controlado. El caso de estudio son
dos aplicaciones reales que se ejecutan fuera del clúster: **Ascenda** y una aplicación de gestión
para una academia de **Brazilian Jiu-Jitsu**.

**Palabras clave:** OpenTelemetry, observabilidad, Elasticsearch, ECK, Kubernetes, k3s, APM, alta
disponibilidad, infraestructura como código, ingeniería del caos.

---

## 1. Introducción

La observabilidad moderna se apoya en tres señales: **trazas**, **métricas** y **logs**. Durante
años, cada fabricante de APM impuso su propio agente y su propio protocolo. **OpenTelemetry (OTel)**,
proyecto de la CNCF, resuelve ese acoplamiento con una especificación, unos SDK y un protocolo
(OTLP) comunes: las aplicaciones se instrumentan una sola vez y el backend pasa a ser una decisión
intercambiable.

En paralelo, la operación de plataformas *stateful* ha migrado hacia **operadores de Kubernetes**,
que codifican el conocimiento operativo (certificados, actualizaciones, recuperación) en software.
ECK es el operador oficial de Elastic y está disponible sin coste con la licencia Basic.

Este proyecto pretende demostrar en la práctica que:

1. es posible construir una plataforma de observabilidad de calidad de producción, on-premise, sin
   agentes propietarios y **sin coste de licencias**;
2. esa plataforma puede ser altamente disponible con recursos modestos (tres hosts físicos);
3. su comportamiento ante fallos se puede **medir** en lugar de suponer.

## 2. Objetivos

| # | Objetivo | Criterio de éxito |
|---|---|---|
| O1 | Instrumentar dos aplicaciones reales con OTel | Trazas, métricas y logs correlacionados en Kibana |
| O2 | Plataforma tolerante a la caída de un host | etcd y Elasticsearch mantienen quórum con 2 de 3 nodos |
| O3 | Pipeline de telemetría sin punto único de fallo | Ningún componente aislado detiene la ingesta |
| O4 | Reproducibilidad total | `terraform apply` → `ansible-playbook` → `helmfile apply` desde cero |
| O5 | Coste de licencias cero | Solo funciones de la licencia Basic (ADR-0005) |
| O6 | Validación empírica | Experimentos E1–E4 documentados con resultados |

## 3. Arquitectura

### 3.1 Vista general

```
 Hosts de aplicaciones (fuera del clúster)                 Clúster k3s (3 VMs KVM, una por host físico)
 ┌──────────────────────────────┐                ┌───────────────────────────────────────────────────┐
 │ Ascenda / BJJ ──OTLP──▶ agente │──OTLP/TLS──▶ │ IP MetalLB ─▶ Gateway EDOT x2 ─▶ Elasticsearch x3 │
 │ (SDK OTel)      otelcol + cola │              │                  ▲                  ▲  (ECK)      │
 └──────────────────────────────┘                │ DaemonSet agente ┘   Kibana (ECK) ──┘             │
                                                 │ Colector cluster-stats ─▶ gateway                 │
                                                 └───────────────────────────────────────────────────┘
```

| Capa | Componente | Gestión |
|---|---|---|
| Cómputo | 3 VMs KVM (Debian 13, 16 GB), una por host físico | Terraform + cloud-init |
| Orquestación | k3s, 3 *servers* con etcd embebido | Ansible |
| Red | MetalLB (modo L2) | Helm |
| Certificados | cert-manager con una CA de laboratorio | Helm |
| Almacenamiento y UI | Elasticsearch ×3 + Kibana | Operador ECK |
| Telemetría | Agente DaemonSet, colector de clúster, gateway EDOT ×2 | OpenTelemetry Operator |

### 3.2 Flujo de la telemetría

1. **Generación.** Las aplicaciones (fuera del clúster) emiten OTLP a un agente local
   (`otelcol-contrib`), que añade métricas de host y logs de `journald`, encola en disco y reenvía
   por TLS a la IP de MetalLB del gateway.
2. **Agente del clúster (DaemonSet).** En cada nodo recoge los logs de los contenedores, métricas
   del kubelet y del host, y enriquece con metadatos de Kubernetes (`k8sattributes`).
3. **Colector de clúster.** Una única réplica recoge el estado de los objetos de Kubernetes y los
   eventos.
4. **Gateway (EDOT, 2 réplicas).** Recibe OTLP, aplica `memory_limiter` y `batch`, y enriquece las
   trazas para el APM de Kibana (`elasticapm`). Es el único componente con credenciales de
   Elasticsearch.
5. **Almacenamiento.** El exportador `elasticsearch` en modo `otel` escribe documentos
   **OTel-native** en *data streams* (`traces-*`, `metrics-*`, `logs-*`).
6. **Visualización.** Kibana (APM, Logs, Metrics, Infrastructure) y dashboards propios.

## 4. Decisiones de diseño

Las decisiones se documentan en formato ADR en [`docs/adr/`](adr/). Resumen:

### 4.1 Nodos como VMs KVM (ADR-0001)

Kubernetes y Elasticsearch necesitan su propio kernel (`vm.max_map_count`, cgroups, sin *swap*).
Con KVM cada nodo es autónomo y el hipervisor queda genérico: `cpu=host`, sin *ballooning* y discos
`virtio-scsi-single` con `iothread`.

### 4.2 ECK sobre k3s (ADR-0004)

- **k3s** con tres *servers* y etcd embebido proporciona un plano de control en alta disponibilidad
  con un consumo de memoria reducido, lo que deja más RAM para Elasticsearch.
- **ECK** gestiona el clúster de Elasticsearch (3 nodos *master + data + ingest*, uno por nodo
  mediante *anti-affinity* obligatoria) y Kibana: certificados TLS internos, usuario `elastic`,
  actualizaciones progresivas y *PodDisruptionBudgets*.
- **Volúmenes `local-path`:** Elasticsearch replica los *shards*, así que el disco local del nodo es
  la opción recomendada y la más rápida.
- **Usuarios declarativos:** el usuario de los colectores (`otel_writer`) y su rol se declaran en
  *Secrets* referenciados por el recurso `Elasticsearch`. La contraseña se genera en la primera
  instalación y nunca está en git.

### 4.3 OpenTelemetry nativo (ADR-0002)

SDK de OTel en las aplicaciones y modo de mapeo `otel` en el exportador. Los componentes
específicos de Elastic quedan confinados al gateway, de modo que cambiar de backend solo afecta a
esa capa.

### 4.4 Colectores en dos niveles con el OpenTelemetry Operator (ADR-0003)

| Nivel | Implementación | Responsabilidad |
|---|---|---|
| Agente | DaemonSet + colector de clúster; `otelcol` en hosts externos | Recogida local, metadatos, *buffer* |
| Gateway | Deployment EDOT ×2 detrás de un Service | TLS, credenciales, enriquecimiento APM, escritura en ES |

El Service de Kubernetes solo enruta a réplicas sanas, por lo que la caída de un gateway no debería
interrumpir la ingesta. Esta hipótesis se comprueba en E2.

### 4.5 Solo licencia Basic (ADR-0005)

Según la matriz oficial de suscripciones *self-managed*, la licencia Basic incluye ECK, la ingesta
OpenTelemetry, APM Server y la aplicación APM, TLS, RBAC, ILM, *snapshots* y las alertas de Kibana
con conectores *Index* y *Server log*. **No** incluye los *service maps* del APM, los SLO, los
conectores de notificación (email, Slack, *webhook*) ni el *machine learning*. Se sustituyen por:

- reglas de umbral sobre el ratio de errores y la latencia p95 (SLI sin presupuesto de error);
- **ElastAlert2** (software libre) para las notificaciones;
- las vistas de dependencias y la cascada de trazas del APM en lugar del mapa de servicios.

## 5. Implementación

### 5.1 Infraestructura (Terraform)

Proveedor `bpg/proxmox` como implementación de referencia: imagen *cloud* de Debian 13,
*cloud-init* y validación de que hay exactamente tres nodos en tres hosts distintos. Terraform
genera el inventario de Ansible, que no se versiona.

### 5.2 Sistema operativo y Kubernetes (Ansible)

| Rol | Función |
|---|---|
| `common` | Paquetes base, zona horaria, `/etc/hosts`, *swap* desactivado |
| `k3s` | `sysctl` (Elasticsearch y *inotify*), configuración e instalación de k3s; el primer nodo inicializa etcd y los demás se unen de uno en uno; copia del *kubeconfig* |
| `otel_agent` | `otelcol-contrib` en los hosts de las aplicaciones, con cola persistente y confianza en la CA del clúster |
| `app_instrumentation` | *Drop-ins* systemd con variables `OTEL_*` |

### 5.3 Plataforma (Helmfile)

Un único `helmfile apply` despliega, en orden y con dependencias explícitas: cert-manager, MetalLB,
el operador ECK, el *chart* propio `lab-platform` (CA, *pool* de IPs, Elasticsearch, Kibana,
credenciales, Service externo del gateway) y el *chart* `opentelemetry-kube-stack`.

### 5.4 Modelo de datos

El modo `otel` escribe en *data streams* separados por señal y *dataset*. La retención se gestiona
con el ciclo de vida de los *data streams* (por ejemplo, 7 días para trazas y 30 para métricas)
mediante plantillas `@custom`.

## 6. Instrumentación de las aplicaciones

- **Auto-instrumentación** sin cambios de código: HTTP, base de datos y clientes salientes.
- **Spans de negocio** en las operaciones clave (por ejemplo, reservas de clase o *check-in* en la
  aplicación BJJ).
- **Correlación logs–trazas** mediante el *bridge* de logs de OTel.
- **Privacidad:** sin datos personales en atributos ni logs.
- **Muestreo:** `parentbased_traceidratio`, configurable por servicio.

## 7. Metodología experimental

Cada experimento se repite **n = 10** veces. Se publican la mediana y el percentil 95.

| ID | Experimento | Métrica | Hipótesis |
|---|---|---|---|
| E1 | Parada abrupta de la VM de un nodo k3s | Tiempo hasta que ECK informa de la degradación; tiempo hasta *green* tras el arranque | El clúster sigue aceptando escrituras en *yellow* y etcd mantiene el quórum |
| E2 | Borrado forzado de un *pod* gateway | Sondas OTLP fallidas a través de la IP de MetalLB; tiempo hasta recuperar las réplicas | Cero o casi cero sondas fallidas |
| E3 | Carga sostenida con k6 (20 VU, 10 min) | Latencia p95 con y sin instrumentación; CPU/RAM de los colectores | *Overhead* de latencia inferior al 5 % |
| E4 | E1 y E2 con generación constante de spans | Spans generados frente a almacenados | Pérdida cero gracias a las colas y reintentos |

## 8. Resultados

> *Pendiente de ejecución. Las tablas se completarán con los datos de `experiments/results/`.*

| Experimento | Mediana | p95 | ¿Hipótesis confirmada? |
|---|---|---|---|
| E1 – detección | – | – | – |
| E1 – recuperación a *green* | – | – | – |
| E2 – sondas fallidas | – | – | – |
| E3 – *overhead* de latencia | – | – | – |
| E4 – spans perdidos | – | – | – |

## 9. Seguridad

- TLS en todos los saltos expuestos: Elasticsearch (ECK), Kibana y OTLP externo (cert-manager).
- Usuario de los colectores con privilegios mínimos (`create_doc` en `logs-*`, `metrics-*` y
  `traces-*`).
- Secretos fuera de git: Ansible Vault (token de k3s) y contraseñas generadas en el clúster.
- CI con `gitleaks`. El repositorio solo contiene valores de ejemplo.

## 10. Limitaciones y trabajo futuro

- Una sola instancia de Kibana (no es crítica para la ingesta).
- El *kubeconfig* apunta al primer nodo: el plano de control es HA, pero el acceso administrativo
  no lo es (mejora: VIP con kube-vip).
- Sin presupuestos de error ni mapa de servicios (limitaciones de la licencia Basic).
- *Tail sampling* (requiere el exportador `loadbalancing`).
- *Snapshots* a almacenamiento S3 compatible con SLM.
- GitOps con Argo CD y aplicación de demostración dentro del clúster.

## 11. Conclusiones

*Se redactarán tras la ejecución de los experimentos.*

## Referencias

1. OpenTelemetry Specification. https://opentelemetry.io/docs/specs/
2. OpenTelemetry Operator y `opentelemetry-kube-stack`. https://github.com/open-telemetry/opentelemetry-helm-charts
3. Elastic Cloud on Kubernetes. https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s
4. Elastic Distributions of OpenTelemetry (EDOT). https://www.elastic.co/docs/reference/opentelemetry
5. Elastic self-managed subscriptions. https://www.elastic.co/subscriptions
6. k3s – High Availability Embedded etcd. https://docs.k3s.io/datastore/ha-embedded
7. MetalLB. https://metallb.io/
8. Principles of Chaos Engineering. https://principlesofchaos.org/

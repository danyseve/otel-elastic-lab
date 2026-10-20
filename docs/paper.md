# Observabilidad *vendor-neutral* con OpenTelemetry y Elasticsearch en alta disponibilidad sobre máquinas virtuales KVM

**Autor:** danyseve · **Versión:** 0.1 (borrador) · **Repositorio:** `github.com/danyseve/otel-elastic-lab`

---

## Resumen

Este trabajo describe el diseño, la implementación y la validación experimental de una plataforma de
observabilidad completa (trazas, métricas y logs) construida exclusivamente con estándares abiertos.
Las aplicaciones y la infraestructura se instrumentan con **OpenTelemetry**. La telemetría pasa por
una arquitectura de colectores en dos niveles (*agent* y *gateway*) y se almacena en un clúster de
**Elasticsearch** de tres nodos desplegado sobre máquinas virtuales KVM, cada una en un host físico
distinto. Toda la plataforma se define como código (Terraform y Ansible) y se valida mediante
experimentos de fallo controlado. El caso de estudio son dos aplicaciones reales: **Ascenda** y una
aplicación de gestión para una academia de **Brazilian Jiu-Jitsu**.

**Palabras clave:** OpenTelemetry, observabilidad, Elasticsearch, APM, alta disponibilidad,
infraestructura como código, ingeniería del caos.

---

## 1. Introducción

La observabilidad moderna se apoya en tres señales: **trazas** (el recorrido de una petición),
**métricas** (agregados numéricos en el tiempo) y **logs** (eventos discretos). Durante años, cada
fabricante de APM impuso su propio agente y su propio protocolo, de modo que cambiar de backend
obligaba a reinstrumentar las aplicaciones.

**OpenTelemetry (OTel)**, proyecto de la CNCF, resuelve ese acoplamiento con una especificación,
unos SDK y un protocolo (OTLP) comunes. Las aplicaciones se instrumentan una sola vez y el backend
pasa a ser una decisión intercambiable.

Este proyecto pretende demostrar en la práctica que:

1. es posible construir una plataforma de observabilidad de calidad de producción sin agentes
   propietarios;
2. esa plataforma puede ser altamente disponible con recursos modestos (tres hosts);
3. su comportamiento ante fallos se puede **medir** en lugar de suponer.

## 2. Objetivos

| # | Objetivo | Criterio de éxito |
|---|---|---|
| O1 | Instrumentar dos aplicaciones reales con OTel | Trazas, métricas y logs correlacionados en Kibana |
| O2 | Clúster ES tolerante a la caída de un nodo | El clúster sigue aceptando escrituras con 2 de 3 nodos |
| O3 | Pipeline de telemetría sin punto único de fallo | Ningún componente aislado detiene la ingesta |
| O4 | Reproducibilidad total | `terraform apply` + `ansible-playbook` desde cero |
| O5 | Validación empírica | Experimentos E1–E4 documentados con resultados |

## 3. Arquitectura

### 3.1 Vista general

La plataforma consta de cuatro máquinas virtuales:

- **es-01, es-02, es-03:** nodos de Elasticsearch (roles *master*, *data* e *ingest*). Cada una
  ejecuta además un *gateway* OTel (EDOT Collector) y un *agent* OTel. es-01 aloja también Kibana.
- **apps:** ejecuta Ascenda y la aplicación BJJ, junto con un *agent* OTel.

Cada VM de Elasticsearch se despliega en un **host físico distinto**, de modo que la pérdida de un
host equivale a la pérdida de un único nodo del clúster.

```
 Aplicaciones (SDK OTel) ──OTLP──▶ Agent local ──OTLP/TLS──▶ VIP gateway ──▶ Gateways (x3) ──▶ Elasticsearch (x3) ◀── Kibana
 Host / logs / ES stats ─────────▶ Agent local ─────────────▶ Gateway local ─┘
```

### 3.2 Flujo de la telemetría

1. **Generación.** Los SDK de OTel (auto-instrumentación más spans de negocio) emiten trazas,
   métricas y logs por OTLP a `127.0.0.1`.
2. **Agente (uno por VM).** Recoge además métricas del host (`hostmetrics`), logs de `journald`,
   logs JSON de Elasticsearch y métricas internas del propio clúster (`elasticsearch` receiver).
   Añade atributos de recurso (`host.name`, `deployment.environment.name`) y encola en disco
   (`file_storage`) lo que no puede entregar.
3. **Gateway (tres instancias).** Recibe OTLP con TLS, aplica `memory_limiter` y `batch`, y
   enriquece las trazas para el APM de Kibana (`elasticapm` processor/connector). El conector
   `elasticapm` genera las métricas agregadas de latencia, *throughput* y tasa de errores.
4. **Almacenamiento.** El exportador `elasticsearch` en modo `otel` escribe documentos
   **OTel-native** en *data streams* (`traces-*`, `metrics-*`, `logs-*`), repartiendo la carga
   entre los tres nodos.
5. **Visualización.** Kibana (Observability → Applications, Hosts, Logs) y dashboards propios.

## 4. Decisiones de diseño

Las decisiones se documentan en formato ADR en [`docs/adr/`](adr/). Este apartado las resume.

### 4.1 Máquinas virtuales KVM frente a contenedores LXC (ADR-0001)

Elasticsearch necesita parámetros de kernel (`vm.max_map_count`), control del *swap* y límites de
memoria predecibles para la JVM. En un contenedor LXC el kernel es el del host, así que esos ajustes
afectan al hipervisor. Con KVM, cada VM tiene su propio kernel y la configuración se asemeja a la de
un entorno de producción en cloud u *on-premise*. Además:

- `cpu=host` expone las instrucciones SIMD (AVX) que Elasticsearch aprovecha.
- El *ballooning* está desactivado: el *heap* de la JVM no debe ser reclamado por el hipervisor.
- Discos `virtio-scsi-single` con `iothread` y `discard`.

### 4.2 Tres nodos *master-eligible*

Un clúster necesita una mayoría de nodos elegibles como *master* para elegir líder: con tres nodos,
el quórum es dos. Por tanto, el clúster tolera la pérdida de un nodo sin *split-brain*. Con una
réplica por shard, cualquier nodo puede caer sin perder datos.

### 4.3 OpenTelemetry nativo frente a agentes APM propietarios (ADR-0002)

Se descartan los agentes APM clásicos en favor de los SDK de OTel y del modo de mapeo `otel` del
exportador. Así, el backend es intercambiable y los datos conservan la semántica de las
*semantic conventions* de OTel.

### 4.4 Colectores en dos niveles (ADR-0003)

| Nivel | Responsabilidad | Motivo |
|---|---|---|
| *Agent* | Recogida local, metadatos de host, *buffer* en disco | Desacopla la app de la red y del backend |
| *Gateway* | TLS, credenciales, enriquecimiento APM, escritura en ES | Centraliza secretos y procesamiento pesado |

Las aplicaciones nunca conocen credenciales de Elasticsearch, y el *agent* solo necesita alcanzar
el *gateway*.

### 4.5 Alta disponibilidad del *gateway*: VIP con VRRP

Los tres *gateways* comparten una IP virtual gestionada por **keepalived**. El *script* de salud
consulta la extensión `health_check` del colector: si el *gateway* activo deja de responder, la VIP
migra a otro nodo en pocos segundos. Se usa VRRP en modo *unicast* para no depender de *multicast*
a través de los puentes virtuales.

Mientras dura la conmutación, el *agent* reintenta indefinidamente (`max_elapsed_time: 0`) y
conserva los datos en la cola persistente, por lo que la conmutación **no debería implicar pérdida
de datos**. Esta hipótesis se comprueba en el experimento E4.

### 4.6 PKI propia

Ansible genera una CA de laboratorio y un certificado por VM (con SAN para nombre, FQDN, IP y, en
los *gateways*, la VIP). La CA se instala en el almacén del sistema, de modo que todos los clientes
(colectores, Kibana, `curl`) verifican TLS sin desactivar comprobaciones.

## 5. Implementación

### 5.1 Infraestructura (Terraform)

- Proveedor `bpg/proxmox` como implementación de referencia.
- Imagen cloud oficial de Debian 13, configurada mediante *cloud-init* (usuario, clave SSH,
  `qemu-guest-agent`).
- Terraform **genera el inventario de Ansible**. Este fichero no se versiona porque contiene las IP
  reales.

### 5.2 Configuración (Ansible)

| Rol | Función |
|---|---|
| `pki` | CA y certificados (en la máquina de control) |
| `common` | Paquetes base, zona horaria, `/etc/hosts`, confianza en la CA |
| `elasticsearch` | Instalación fijada a una versión, `sysctl`, TLS, *heap*, usuarios y roles |
| `kibana` | Instalación, TLS, conexión a los tres nodos |
| `otel_gateway` | EDOT Collector como servicio systemd |
| `keepalived` | VIP del *gateway* con *health check* |
| `otel_agent` | `otelcol-contrib` con cola persistente |
| `app_instrumentation` | *Drop-ins* systemd con variables `OTEL_*` |

**Principio de mínimo privilegio:** los colectores usan el usuario `otel_writer`, que solo puede
crear documentos en `logs-*`, `metrics-*` y `traces-*` y leer estadísticas del clúster.

### 5.3 Modelo de datos

El modo `otel` escribe en *data streams* separados por señal y por *dataset*. La retención se
gestiona con el ciclo de vida de los *data streams* (p. ej., 7 días para trazas y 30 para métricas)
mediante plantillas `@custom`, sin modificar las plantillas gestionadas por Elastic.

## 6. Instrumentación de las aplicaciones

- **Auto-instrumentación** sin cambios de código: HTTP, base de datos y clientes salientes.
- **Spans de negocio** en las operaciones clave de cada aplicación (por ejemplo, reservas de clase
  o *check-in* en la aplicación BJJ).
- **Correlación logs–trazas:** el *bridge* de logs de OTel añade `trace_id` y `span_id` a cada
  línea.
- **Privacidad:** no se registran datos personales en atributos ni en logs, solo identificadores.
- **Muestreo:** `parentbased_traceidratio`, configurable por servicio.

## 7. Metodología experimental

Cada experimento se repite **n = 10** veces. Se publican la mediana y el percentil 95.

| ID | Experimento | Métrica | Hipótesis |
|---|---|---|---|
| E1 | Parada abrupta (`stop`) de un nodo ES | Tiempo de detección; tiempo hasta *green* tras el arranque | El clúster sigue aceptando escrituras en *yellow* |
| E2 | Parada del *gateway* que posee la VIP | Tiempo sin ingesta a través de la VIP | Menos de 5 s |
| E3 | Carga sostenida con k6 (20 VU, 10 min) | Latencia p95 de la app con y sin instrumentación; CPU/RAM de los colectores | *Overhead* de latencia inferior al 5 % |
| E4 | E2 con generación constante de spans | Spans generados frente a spans almacenados | Pérdida cero gracias a la cola persistente |

Los *scripts* están en [`experiments/`](../experiments/).

## 8. Resultados

> *Pendiente de ejecución. Las tablas se completarán con los datos de `experiments/results/`.*

| Experimento | Mediana | p95 | ¿Hipótesis confirmada? |
|---|---|---|---|
| E1 – detección | – | – | – |
| E1 – recuperación a *green* | – | – | – |
| E2 – corte de ingesta | – | – | – |
| E3 – *overhead* de latencia | – | – | – |
| E4 – spans perdidos | – | – | – |

## 9. Seguridad

- TLS en todos los saltos de red (transporte y HTTP de ES, Kibana, OTLP hacia los *gateways*).
- Secretos en Ansible Vault. CI con `gitleaks` para evitar filtraciones.
- Usuarios dedicados con privilegios mínimos.
- El repositorio no contiene IP, dominios ni topología reales: solo valores de ejemplo.

## 10. Limitaciones y trabajo futuro

- Kibana es una única instancia (no es crítica para la ingesta).
- Falta muestreo por cola (*tail sampling*), que requiere enrutar por `trace_id` (exportador
  `loadbalancing`).
- SLO, dashboards y alertas como código con el proveedor Terraform `elastic/elasticstack`.
- Aplicación de demostración políglota para que cualquiera pueda reproducir el laboratorio.
- Perfilado continuo (señal *profiles* de OTel).
- Instantáneas (*snapshots*) de ES a almacenamiento S3 compatible.

## 11. Conclusiones

*Se redactarán tras la ejecución de los experimentos.*

## Referencias

1. OpenTelemetry Specification. https://opentelemetry.io/docs/specs/
2. OpenTelemetry Collector – *Deployment patterns (agent / gateway)*. https://opentelemetry.io/docs/collector/deployment/
3. Elastic Distributions of OpenTelemetry (EDOT). https://www.elastic.co/docs/reference/opentelemetry
4. Elasticsearch – *Discovery and cluster formation*. https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation
5. Keepalived – VRRP. https://keepalived.readthedocs.io/
6. Principles of Chaos Engineering. https://principlesofchaos.org/

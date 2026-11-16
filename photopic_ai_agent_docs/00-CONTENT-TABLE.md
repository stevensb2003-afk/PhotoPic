# Índice Maestro de Navegación Documental (`CONTENT TABLE`)
> **ID Documento**: `DOC-00` | **Módulo Sistema**: `global-router` | **Rutas**: `Todas`
> **Roles con Acceso**: `Router Maestro para Agente IA Multi-Rol y Centro de Ayuda Interno`
> **Propósito LLM**: Tabla central de enrutamiento con módulos, perfiles operativos y coordenadas exactas `Lxxx-Lyyy`.

<!-- TOC:START -->
## Índice de Navegación Rápida por Líneas (Para IA y Lectura Directa)
> **Instrucción para Agentes IA**: Lee únicamente el rango `Lxxx-Lyyy` correspondiente al subtema y rol del usuario para ahorrar contexto.

| # | Sección / Subtema / Proceso | Nivel de Rol | Líneas |
| :--- | :--- | :--- | :--- |
| 1 | 1. Protocolo de Lectura Eficiente por Perfil | `REFERENCIA-RBAC` | `L019-L024` |
| 2 | 2. Matriz Rápida de Módulos y Perfiles del Sistema | `REFERENCIA-RBAC` | `L025-L035` |
| 3 | 3. Directorio Global de Archivos y Coordenadas de Línea | `TODOS` | `L036-L072` |
| 4 | ↳ Catálogo Maestro de Archivos de Documentación | `TODOS` | `L039-L049` |
| 5 | ↳ Mapa Directo de Secciones `H2` y Coordenadas de Línea por Archivo | `TODOS` | `L050-L072` |
<!-- TOC:END -->

## 1. Protocolo de Lectura Eficiente por Perfil [ROL: REFERENCIA-RBAC]

1. Identifica si la consulta corresponde a operación en sesión (`FOTOGRAFO` / `ASISTENTE`), configuración de equipo/hardware (`ADMIN-EQUIPO`) o procesos automáticos en segundo plano (`SISTEMA-AUTO`).
2. Selecciona el archivo `DOC-XX` correspondiente en el Directorio Global de la Sección 3 y lee primero su tabla de contenido `<!-- TOC:START -->`.
3. Responde únicamente con pasos accionables reales presentes en la interfaz vigente de PhotoPic (`v2.2.0`).

## 2. Matriz Rápida de Módulos y Perfiles del Sistema [ROL: REFERENCIA-RBAC]

| Módulo ID | Nombre Comercial | Acceso Principal | Alcance Operativo (`FOTOGRAFO` / `ASISTENTE`) | Alcance Configuración (`ADMIN-EQUIPO`) | Documento |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `global` | Arquitectura y Ayuda | Barra superior (`?` / `⌘?`) | Consultar guías, atajos y estado de carpetas | Elegir Carpeta Raíz Global y bookmarks | `01-arquitectura-global-y-perfiles.md` |
| `hardware` | Asistente y Auditoría IA | Primer arranque / `General y Rendimiento` | Ver perfil activo (`Estudio Completo`, `Equilibrado`, `Modo Ligero`) | Re-auditar hardware, apagar/prender IA y poses | `02-modulo-asistente-y-auditoria-hardware.md` |
| `tether` | Captura USB, Wi-Fi y Watchfolder | Píldora USB / `Vincular Carpeta / Wi-Fi...` | Ver estado en vivo y recibir disparos | Guardar alias, liberar `PTPCamera`, activar JPG fallback | `03-modulo-captura-usb-wifi-y-watchfolder.md` |
| `culling` | Culling RAW, IA y Archivadas | Pestañas `Filtrar` y `Archivadas` | Navegar, Zoom 1:1, aprobar, archivar, deshacer y recuperar | Eliminar definitivamente o vaciar `Archivadas/` | `04-modulo-culling-raw-ia-y-archivadas.md` |
| `auto` | Automatizaciones y Pares RAW+JPG | Segundo plano | N/A (automático al ingerir y clasificar) | N/A (reglas inmutables de disco y XMP) | `05-automatizaciones-flujos-y-carpetas.md` |
| `egm-map` | Mapa de Capas EGM | Referencia técnica | N/A | N/A | `06-mapa-capas-egm-referencia.md` |

## 3. Directorio Global de Archivos y Coordenadas de Línea [ROL: TODOS]

<!-- MASTER-INDEX:START -->
### Catálogo Maestro de Archivos de Documentación

| Archivo | ID | Módulo Sistema | Líneas | Contenido Funcional Principal |
| :--- | :--- | :--- | :--- | :--- |
| `01-arquitectura-global-y-perfiles.md` | `DOC-01` | `global` | `46` | Explica la navegación general de PhotoPic, perfiles de uso en estudio y operación del Centro de Ayuda interno. |
| `02-modulo-asistente-y-auditoria-hardware.md` | `DOC-02` | `hardware-auditor` | `49` | Detalla cómo PhotoPic audita CPU, RAM, GPU Metal y Apple Neural Engine, y cómo desactivar o regular la IA. |
| `03-modulo-captura-usb-wifi-y-watchfolder.md` | `DOC-03` | `tether-discovery` | `46` | Guía paso a paso para conectar cámaras DSLR/Mirrorless, smartphones Android/iPhone, transmisores Wi-Fi y Watchfolders. |
| `04-modulo-culling-raw-ia-y-archivadas.md` | `DOC-04` | `culling-workspace` | `55` | Explica paso a paso el visor RAW GPU, Zoom 1:1, filtros IA, movimiento sincronizado RAW+JPG y borrado definitivo. |
| `05-automatizaciones-flujos-y-carpetas.md` | `DOC-05` | `automations` | `36` | Documenta las reglas automáticas en segundo plano y el flujo completo End-to-End desde la captura hasta la entrega. |
| `06-mapa-capas-egm-referencia.md` | `DOC-06` | `egm-reference` | `30` | Vincula cada documento funcional `DOC-XX` con las rutas exactas de modelos, servicios, ViewModels y vistas en disco. |

### Mapa Directo de Secciones `H2` y Coordenadas de Línea por Archivo

| Archivo Destino | Tema / Bloque Funcional | Nivel de Rol | Rango Exacto |
| :--- | :--- | :--- | :--- |
| `01-arquitectura-global-y-perfiles.md` | 1. Propósito de Negocio y Principio Sin Catálogo Cerrado | `TODOS` | `L019-L022` |
| `01-arquitectura-global-y-perfiles.md` | 2. Matriz de Perfiles de Trabajo en Estudio | `REFERENCIA-RBAC` | `L023-L030` |
| `01-arquitectura-global-y-perfiles.md` | 3. Navegación Principal y Centro de Ayuda Interno | `TODOS` | `L031-L037` |
| `01-arquitectura-global-y-perfiles.md` | 4. Estructura de Carpetas por Sesión | `TODOS` | `L038-L046` |
| `02-modulo-asistente-y-auditoria-hardware.md` | 1. Propósito y Origen del Motor Neural Engine | `TODOS` | `L020-L023` |
| `02-modulo-asistente-y-auditoria-hardware.md` | 2. Qué Inspecciona el Auditor al Arrancar | `SISTEMA-AUTO` | `L024-L030` |
| `02-modulo-asistente-y-auditoria-hardware.md` | 3. Reglas de Recomendación Automática de Perfiles | `SISTEMA-AUTO` | `L031-L036` |
| `02-modulo-asistente-y-auditoria-hardware.md` | 4. Procesos Paso a Paso | `ADMIN-EQUIPO` | `L037-L049` |
| `03-modulo-captura-usb-wifi-y-watchfolder.md` | 1. Propósito de Negocio y Modos de Captura | `TODOS` | `L020-L023` |
| `03-modulo-captura-usb-wifi-y-watchfolder.md` | 2. Procesos Operativos Paso a Paso | `FOTOGRAFO` | `L024-L040` |
| `03-modulo-captura-usb-wifi-y-watchfolder.md` | 3. Reglas de Perfil de Dispositivo y Escudo Anti-Galería Vieja | `ADMIN-EQUIPO` | `L041-L046` |
| `04-modulo-culling-raw-ia-y-archivadas.md` | 1. Visor Central RAW GPU y Atajos de Estudio | `FOTOGRAFO` | `L021-L032` |
| `04-modulo-culling-raw-ia-y-archivadas.md` | 2. Filtros de IA Offline y Etiquetas Personalizadas | `FOTOGRAFO` | `L033-L043` |
| `04-modulo-culling-raw-ia-y-archivadas.md` | 3. Gestión de `Archivadas`: Recuperar o Eliminar Definitivamente | `ADMIN-EQUIPO` | `L044-L055` |
| `05-automatizaciones-flujos-y-carpetas.md` | 1. Automatizaciones en Segundo Plano | `SISTEMA-AUTO` | `L016-L029` |
| `05-automatizaciones-flujos-y-carpetas.md` | 2. Flujo End-to-End (E2E) Completo en Estudio | `TODOS` | `L030-L036` |
| `06-mapa-capas-egm-referencia.md` | 1. Mapa de Correspondencia `DOC-XX` vs Código Fuente | `REFERENCIA-RBAC` | `L016-L025` |
| `06-mapa-capas-egm-referencia.md` | 2. Invariantes de Arquitectura y Verificación | `SISTEMA-AUTO` | `L026-L030` |
<!-- MASTER-INDEX:END -->

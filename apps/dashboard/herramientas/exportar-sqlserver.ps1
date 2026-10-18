<#
  Exporta los datos de Dashboard Empresarial desde SQL Server a UN archivo .sql listo para cargar en PostgreSQL (Oracle).

  Que hace:  SOLO LEE de SQL Server (SELECT). No cambia nada en el origen.
  Donde correrlo:  en cualquier PC o servidor Windows que llegue al SQL Server (el servidor de la oficina o una PC de la oficina).
  Como:  abre "Windows PowerShell" (el que viene con Windows, NO PowerShell 7) y corre:
            powershell -ExecutionPolicy Bypass -File .\exportar-sqlserver.ps1
         Te pregunta el servidor, la base y como entrar. La clave se escribe oculta (un * por caracter); nunca se guarda.
  Resultado:  dashboard-datos-AAAAMMDD-HHMM.sql   (CONTIENE correos, nombres y las claves cifradas de los usuarios:
              es un archivo SENSIBLE; subelo al bucket privado de Oracle y borralo de tu PC).

  Parametros opcionales (para no escribir las respuestas):
     -Servidor "SERVIDOR\INSTANCIA"  -Base "NombreDeLaBase"  -Usuario "usuario_sql"  -Salida "C:\ruta\archivo.sql"
  Sin -Usuario entra con la cuenta de Windows con la que estas conectado.
#>
param(
  [string]$Servidor,
  [string]$Base,
  [string]$Usuario,
  [string]$Salida
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function Leer([string]$texto, [string]$defecto) {
  $sufijo = ''
  if ($defecto) { $sufijo = " [Enter = $defecto]" }
  $v = Read-Host ($texto + $sufijo)
  if ([string]::IsNullOrWhiteSpace($v)) { return $defecto }
  return $v.Trim()
}

# Tablas que usa el sistema, en el orden en que se cargan. Las columnas son las mismas que en db/schema.sql del backend.
$tablas = @(
  @{ Esquema = 'seguridad'; Tabla = 'Roles';             Obligatoria = $false; Id = 'id_rol';
     Cols = @('id_rol', 'nombre', 'descripcion') },
  @{ Esquema = 'comercial'; Tabla = 'Empresas';          Obligatoria = $true;  Id = 'id_empresa';
     Cols = @('id_empresa', 'nombre', 'ruc', 'estado', 'fecha_creacion') },
  @{ Esquema = 'seguridad'; Tabla = 'Usuarios';          Obligatoria = $true;  Id = 'id_usuario';
     Cols = @('id_usuario', 'id_empresa', 'id_rol', 'username', 'email', 'nombre_completo', 'password_hash', 'estado', 'fecha_creacion') },
  @{ Esquema = 'reportes';  Tabla = 'Dashboards';        Obligatoria = $true;  Id = 'id_dashboard';
     Cols = @('id_dashboard', 'codigo', 'nombre', 'descripcion', 'estado', 'fecha_creacion') },
  @{ Esquema = 'reportes';  Tabla = 'DashboardPeriodos'; Obligatoria = $true;  Id = 'id_dashboard_periodo';
     Cols = @('id_dashboard_periodo', 'id_dashboard', 'periodo', 'url_powerbi', 'url_mega', 'fecha_creacion') },
  @{ Esquema = 'comercial'; Tabla = 'EmpresaDashboards'; Obligatoria = $true;  Id = 'id_empresa_dashboard';
     Cols = @('id_empresa_dashboard', 'id_empresa', 'id_dashboard', 'fecha_asignacion', 'estado', 'fecha_desactivacion') }
)

Write-Host ''
Write-Host '== Exportar Dashboard Empresarial (SQL Server -> archivo .sql para PostgreSQL)'
Write-Host '   Solo lee. No modifica nada en SQL Server.'
Write-Host ''

if (-not $Servidor) { $Servidor = Leer 'Servidor SQL (ej. localhost, SERVIDOR\SQLEXPRESS o una IP)' 'localhost' }
if (-not $Base) { $Base = Leer 'Nombre de la base de datos' '' }
if (-not $Base) { throw 'Falta el nombre de la base de datos.' }
if (-not $PSBoundParameters.ContainsKey('Usuario')) {
  $Usuario = Leer 'Usuario de SQL Server (Enter = entrar con tu cuenta de Windows)' ''
}

$conn = New-Object System.Data.SqlClient.SqlConnection
$cadena = "Server=$Servidor;Database=$Base;TrustServerCertificate=True;Encrypt=False;Connect Timeout=20;Application Name=exportar-dashboard"
if ($Usuario) {
  $clave = Read-Host 'Clave de SQL Server (se escribe oculta)' -AsSecureString
  Write-Host ("   recibido: {0} caracteres" -f $clave.Length)
  $clave.MakeReadOnly()
  $conn.ConnectionString = $cadena
  $conn.Credential = New-Object System.Data.SqlClient.SqlCredential($Usuario, $clave)
} else {
  $conn.ConnectionString = $cadena + ';Integrated Security=True'
}

try {
  $conn.Open()
} catch {
  throw ("No pude entrar a SQL Server ({0}). Revisa servidor, base, usuario y clave. Detalle: {1}" -f $Servidor, $_.Exception.Message)
}

function Consulta([string]$sql) {
  $cmd = $conn.CreateCommand()
  $cmd.CommandText = $sql
  $cmd.CommandTimeout = 300
  $tabla = New-Object System.Data.DataTable
  $adaptador = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
  [void]$adaptador.Fill($tabla)
  return , $tabla
}
function Numero([string]$sql) {
  $t = Consulta $sql
  return [int64]$t.Rows[0][0]
}

# ---------------------------------------------------------------- 1. Que hay en la base
Write-Host ''
Write-Host ("== Conectado a {0} / {1}" -f $Servidor, $Base)
$lista = Consulta @'
SELECT s.name AS esquema, t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY s.name, t.name
'@
$columnas = Consulta 'SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS'

Write-Host '   Tablas de la base:'
foreach ($fila in $lista.Rows) {
  $nombreCompleto = '{0}.{1}' -f $fila.esquema, $fila.tabla
  $usada = $tablas | Where-Object { $_.Esquema -ieq $fila.esquema -and $_.Tabla -ieq $fila.tabla }
  if ($usada) { $marca = 'se copia' } else { $marca = 'NO se copia (el sistema no la usa)' }
  Write-Host ("     {0,-40} {1,8} filas   {2}" -f $nombreCompleto, $fila.filas, $marca)
}

$problemas = @()
foreach ($t in $tablas) {
  $existe = $lista.Rows | Where-Object { $_.esquema -ieq $t.Esquema -and $_.tabla -ieq $t.Tabla }
  $t.Existe = [bool]$existe
  if (-not $existe) {
    if ($t.Obligatoria) { $problemas += ("Falta la tabla {0}.{1}" -f $t.Esquema, $t.Tabla) }
    continue
  }
  $presentes = @($columnas.Rows | Where-Object { $_.TABLE_SCHEMA -ieq $t.Esquema -and $_.TABLE_NAME -ieq $t.Tabla } | ForEach-Object { $_.COLUMN_NAME })
  foreach ($c in $t.Cols) {
    if ($presentes -notcontains $c) { $problemas += ("A {0}.{1} le falta la columna {2}" -f $t.Esquema, $t.Tabla, $c) }
  }
  $sobran = @($presentes | Where-Object { $t.Cols -notcontains $_ })
  if ($sobran.Count -gt 0) {
    Write-Host ("   AVISO: {0}.{1} tiene columnas que el sistema no usa y NO se copian: {2}" -f $t.Esquema, $t.Tabla, ($sobran -join ', ')) -ForegroundColor Yellow
  }
}
if ($problemas.Count -gt 0) {
  $problemas | ForEach-Object { Write-Host ("   ERROR: " + $_) -ForegroundColor Red }
  throw 'Esta base no tiene la forma esperada. Revisa que sea la base correcta (arriba estan las tablas que existen).'
}

# ---------------------------------------------------------------- 2. Revisiones (solo avisan)
Write-Host ''
Write-Host '== Revision de los datos (solo avisa, no bloquea)'
$revisiones = @(
  @{ Texto = 'usuarios con el mismo nombre (sin distinguir mayusculas)';
     Sql = 'SELECT COUNT(*) FROM (SELECT LOWER(username) u FROM [seguridad].[Usuarios] GROUP BY LOWER(username) HAVING COUNT(*) > 1) x';
     Grave = $true },
  @{ Texto = 'asignaciones repetidas (misma empresa y dashboard)';
     Sql = 'SELECT COUNT(*) FROM (SELECT id_empresa, id_dashboard FROM [comercial].[EmpresaDashboards] GROUP BY id_empresa, id_dashboard HAVING COUNT(*) > 1) x';
     Grave = $true },
  @{ Texto = 'usuarios cuya empresa no existe';
     Sql = 'SELECT COUNT(*) FROM [seguridad].[Usuarios] WHERE id_empresa IS NOT NULL AND id_empresa NOT IN (SELECT id_empresa FROM [comercial].[Empresas])';
     Grave = $false },
  @{ Texto = 'asignaciones que apuntan a una empresa o dashboard que no existe';
     Sql = 'SELECT COUNT(*) FROM [comercial].[EmpresaDashboards] WHERE id_empresa NOT IN (SELECT id_empresa FROM [comercial].[Empresas]) OR id_dashboard NOT IN (SELECT id_dashboard FROM [reportes].[Dashboards])';
     Grave = $false },
  @{ Texto = 'periodos que apuntan a un dashboard que no existe';
     Sql = 'SELECT COUNT(*) FROM [reportes].[DashboardPeriodos] WHERE id_dashboard NOT IN (SELECT id_dashboard FROM [reportes].[Dashboards])';
     Grave = $false },
  @{ Texto = 'usuarios con rol distinto de 1 (administrador) o 2 (cliente)';
     Sql = 'SELECT COUNT(*) FROM [seguridad].[Usuarios] WHERE id_rol IS NULL OR id_rol NOT IN (1, 2)';
     Grave = $false }
)
$hayGraves = $false
foreach ($r in $revisiones) {
  $n = Numero $r.Sql
  if ($n -eq 0) {
    Write-Host ("   OK     0 {0}" -f $r.Texto)
  } else {
    Write-Host ("   AVISO  {0} {1}" -f $n, $r.Texto) -ForegroundColor Yellow
    if ($r.Grave) { $hayGraves = $true }
  }
}
if ($hayGraves) {
  Write-Host '   Los avisos de repetidos impediran la carga en PostgreSQL (alli esos datos son unicos). Avisame antes de seguir.' -ForegroundColor Red
}

# ---------------------------------------------------------------- 3. Archivo .sql
function ValorSql($v) {
  if ($null -eq $v -or $v -is [System.DBNull]) { return 'NULL' }
  if ($v -is [string]) { return "'" + $v.Replace([string][char]0, '').Replace("'", "''") + "'" }
  if ($v -is [datetime]) { return "'" + $v.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff", $inv) + "Z'" }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [int16] -or $v -is [int32] -or $v -is [int64] -or $v -is [byte]) { return ([int64]$v).ToString($inv) }
  if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) { return ([System.Convert]::ToString($v, $inv)) }
  return "'" + ([string]$v).Replace([string][char]0, '').Replace("'", "''") + "'"
}

if (-not $Salida) { $Salida = '.\dashboard-datos-{0}.sql' -f (Get-Date -Format 'yyyyMMdd-HHmm') }
$Salida = [System.IO.Path]::GetFullPath($Salida)
$escritor = New-Object System.IO.StreamWriter($Salida, $false, (New-Object System.Text.UTF8Encoding($false)))
$escritor.NewLine = "`n"
$resumen = @()
try {
  $escritor.WriteLine('-- Dashboard Empresarial: datos exportados de SQL Server para PostgreSQL')
  $escritor.WriteLine(('-- Origen: {0} / {1}   Fecha: {2}' -f $Servidor, $Base, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
  $escritor.WriteLine('-- CONTIENE DATOS PERSONALES Y CLAVES CIFRADAS: no compartir, no subir a GitHub.')
  $escritor.WriteLine("SET client_encoding = 'UTF8';")
  $escritor.WriteLine('SET standard_conforming_strings = on;')
  $escritor.WriteLine('')

  foreach ($t in $tablas) {
    if (-not $t.Existe) { continue }
    $destino = '{0}."{1}"' -f $t.Esquema, $t.Tabla
    $datos = Consulta ('SELECT {0} FROM [{1}].[{2}] ORDER BY [{3}]' -f (($t.Cols | ForEach-Object { '[' + $_ + ']' }) -join ', '), $t.Esquema, $t.Tabla, $t.Id)
    $total = $datos.Rows.Count
    $t.Total = $total
    $resumen += ('{0}.{1}: {2}' -f $t.Esquema, $t.Tabla, $total)
    $escritor.WriteLine(('-- {0}: {1} filas' -f $destino, $total))
    $lote = New-Object System.Collections.Generic.List[string]
    $emitir = {
      if ($lote.Count -eq 0) { return }
      $sentencia = 'INSERT INTO {0} ({1}) OVERRIDING SYSTEM VALUE VALUES' -f $destino, ($t.Cols -join ', ')
      $escritor.WriteLine($sentencia)
      $escritor.Write(($lote -join (",`n")))
      if ($t.Tabla -eq 'Roles') {
        $escritor.WriteLine("`nON CONFLICT (id_rol) DO UPDATE SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion;")
      } else {
        $escritor.WriteLine(';')
      }
      $lote.Clear()
    }
    foreach ($fila in $datos.Rows) {
      $valores = foreach ($c in $t.Cols) { ValorSql $fila[$c] }
      $lote.Add('(' + ($valores -join ', ') + ')')
      if ($lote.Count -ge 200) { & $emitir }
    }
    & $emitir
    $escritor.WriteLine('')
  }

  $escritor.WriteLine('-- El proximo id que se genere sigue despues del ultimo copiado')
  foreach ($t in $tablas) {
    if (-not $t.Existe) { continue }
    $destino = '{0}."{1}"' -f $t.Esquema, $t.Tabla
    $linea = 'SELECT setval(pg_get_serial_sequence(''{0}'', ''{1}''), GREATEST((SELECT COALESCE(MAX({1}), 0) FROM {0}), 1), (SELECT COUNT(*) FROM {0}) > 0);' -f $destino, $t.Id
    $escritor.WriteLine($linea)
  }
  $escritor.WriteLine('')

  $escritor.WriteLine('-- Si falta una sola fila, todo se deshace')
  $escritor.WriteLine('DO $$')
  $escritor.WriteLine('BEGIN')
  foreach ($t in $tablas) {
    if (-not $t.Existe -or $t.Tabla -eq 'Roles') { continue }
    $destino = '{0}."{1}"' -f $t.Esquema, $t.Tabla
    $escritor.WriteLine(('  IF (SELECT COUNT(*) FROM {0}) <> {1} THEN RAISE EXCEPTION ''{0}: se esperaban {1} filas y hay %'', (SELECT COUNT(*) FROM {0}); END IF;' -f $destino, $t.Total))
  }
  $escritor.WriteLine('END $$;')
} finally {
  $escritor.Dispose()
  $conn.Close()
}

# ---------------------------------------------------------------- 4. Resumen
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Salida).Hash
$tamano = [math]::Round((Get-Item -LiteralPath $Salida).Length / 1KB, 1)
Write-Host ''
Write-Host '== Listo' -ForegroundColor Green
$resumen | ForEach-Object { Write-Host ('   ' + $_) }
Write-Host ''
Write-Host ("   Archivo: {0}  ({1} KB)" -f $Salida, $tamano)
Write-Host ("   SHA256:  {0}" -f $hash)
Write-Host ''
Write-Host '   Siguiente paso: subir ese archivo al bucket sulotec-backups de Oracle, carpeta externos/dashboard/ (ver el README del kit).'
Write-Host '   Contiene correos, nombres y claves cifradas: cuando termine la carga, borralo de esta PC.'

let
    // Repoperativo_Transformado (detalle): quitado el agrupado y sin columnas DIAS_MORA_MAX ni RISK_SALDO
    rutaBase = "C:\Users\omjac\Documents\OMAR\ITTIVA\PROYECTOS 2025\MIGRACION TUIIO\repoperativo",
    rutaOficinas = rutaBase & "\Oficinas-Zona-Region.csv",

    TrimColumnName = (n as text) as text => Text.Trim(n),

    // Fuente unificada
    SourceRep = Repoperativo_Source,

    // Tipado limitado sobre las columnas que usaremos (no forzamos DIAS MORA a Int64 para permitir listas/variantes)
    #"Tipo cambiado limitado" = Table.TransformColumnTypes(
        SourceRep,
        {
            {"OFICINA", type text},
            {"REGION", type text},
            {"CONTRATO", Int64.Type},
            {"NOMBRE DEL ASESOR", type text},
            {"PRODUCTO DE PRESTAMOS", type text},
            {"SUBPRODUCTO PRESTAMO", type text},
            {"FECHA DESEMBOLSO", type date},
            {"ESTATUS DEL CREDITO", type text},
            {"SALDO CAP", type number},
            {"SALDO INTERESES", type number},
            {"SALDO REAL EXIGIBLE", type number},
            {"DIAS MORA", type any},
            {"CARTERA EN RIESGO", type number},
            {"FILE PATHS", type text},
            {"FECHA DE COSECHA", type text}
        }
    ),

    // Asegurar que la columna CLIENTE COBIS existe; si no, crearla con nulls (texto inicialmente)
    #"Asegurar CLIENTE COBIS" =
        if List.Contains(Table.ColumnNames(#"Tipo cambiado limitado"), "CLIENTE COBIS") then
            #"Tipo cambiado limitado"
        else
            Table.AddColumn(#"Tipo cambiado limitado", "CLIENTE COBIS", each null, type text),

    // Convertir CLIENTE COBIS a entero seguro (Int64). Si no se puede convertir queda null.
    #"CLIENTE COBIS Convertido" = Table.TransformColumns(
        #"Asegurar CLIENTE COBIS",
        {{"CLIENTE COBIS", each try Int64.From(Number.FromText(Text.Trim(Text.From(_)))) otherwise null, Int64.Type}}
    ),

    // Crear clave normalizada en la tabla principal (Trim + Upper) para matching más robusto
    SourceWithKey = Table.AddColumn(
        #"CLIENTE COBIS Convertido",
        "__REGION_KEY",
        each if Record.HasFields(_, "REGION") and _[REGION] <> null
             then Text.Trim(Text.Upper(Text.From(_[REGION])))
             else null,
        type text
    ),

    // Cargar oficinas desde la consulta preparada si existe; si no, fallback desde CSV
    OficTry = try Oficinas_Source otherwise null,
    OficFinal =
        if OficTry <> null then
            Table.Buffer(OficTry)
        else
            let
                OrigenOficinas = Csv.Document(File.Contents(rutaOficinas), [Delimiter = ",", Encoding = 1252, QuoteStyle = QuoteStyle.None]),
                #"Encabezados Oficinas" = Table.PromoteHeaders(OrigenOficinas, [PromoteAllScalars = true]),
                #"Tipo Cambiado Oficinas" = Table.TransformColumnTypes(#"Encabezados Oficinas", {{"REGION", type text}, {"ZONA", type text}}),
                #"Filas Filtradas Oficinas" = Table.SelectRows(#"Tipo Cambiado Oficinas", each ([REGION] <> "Centralizadora" and [REGION] <> null and Text.Trim([REGION]) <> "")),
                OficinasUnicas = Table.Distinct(#"Filas Filtradas Oficinas", {"REGION"})
            in
                Table.Buffer(OficinasUnicas),

    // Añadir la misma clave normalizada a Oficinas para el join
    OficWithKey = Table.AddColumn(
        OficFinal,
        "__REGION_KEY",
        each if Record.HasFields(_, "REGION") and [REGION] <> null
             then Text.Trim(Text.Upper(Text.From([REGION])))
             else null,
        type text
    ),

    OficBuffer = Table.Buffer(OficWithKey),

    // JOIN por la clave normalizada - JoinKind.Inner (mantener el comportamiento original)
    #"Combinar Consultas" = Table.NestedJoin(
        SourceWithKey, {"__REGION_KEY"},
        OficBuffer, {"__REGION_KEY"},
        "DataOficinas",
        JoinKind.Inner
    ),

    // Expandir ZONA desde las oficinas
    #"Expandir DataOficinas (zona)" = Table.ExpandTableColumn(#"Combinar Consultas", "DataOficinas", {"ZONA"}, {"ZONA"}),

    // Quitar columna auxiliar de clave para no dejarla en resultados
    #"Quitar Clave Auxiliar" = Table.RemoveColumns(#"Expandir DataOficinas (zona)", {"__REGION_KEY"}),

    // Selección temprana de columnas necesarias (detalle por fila)
    #"Columnas Necesarias Seleccionadas" = Table.SelectColumns(#"Quitar Clave Auxiliar", {
        "FECHA DE COSECHA", "OFICINA", "REGION", "ZONA", "CONTRATO", "CLIENTE COBIS",
        "NOMBRE DEL ASESOR", "PRODUCTO DE PRESTAMOS", "SUBPRODUCTO PRESTAMO",
        "FECHA DESEMBOLSO", "ESTATUS DEL CREDITO", "SALDO CAP", "SALDO INTERESES",
        "SALDO REAL EXIGIBLE", "DIAS MORA", "CARTERA EN RIESGO"
    }),

    // Normalizar nombres de encabezado
    #"Nombres Recortados" = Table.TransformColumnNames(#"Columnas Necesarias Seleccionadas", each TrimColumnName(_)),

    // Convertir FECHA DE COSECHA (texto "yyyyMMdd") a tipo date de forma segura
    #"FECHA COSECHA a Date" = Table.TransformColumns(
        #"Nombres Recortados",
        {
            {"FECHA DE COSECHA",
                each let
                    s = Text.Trim( Text.From( _ ) ),
                    conv =
                        if s = null or s = "" then
                            null
                        else
                            try
                                #date(
                                    Number.FromText(Text.Start(s,4)),
                                    Number.FromText(Text.Range(s,4,2)),
                                    Number.FromText(Text.End(s,2))
                                )
                            otherwise null
                in
                    conv,
                type date
            }
        }
    ),

    // Eliminar duplicados exactos (opcional para limpiar filas repetidas)
    #"Filas Unicas Previas" = Table.Distinct(#"FECHA COSECHA a Date"),

    // Reordenar columnas en la salida final (CLIENTE COBIS entre CONTRATO y NOMBRE DEL ASESOR)
    #"Columnas Reordenadas (detalle)" = Table.ReorderColumns(#"Filas Unicas Previas", {
        "FECHA DE COSECHA",
        "OFICINA",
        "REGION",
        "ZONA",
        "CONTRATO",
        "CLIENTE COBIS",
        "NOMBRE DEL ASESOR",
        "PRODUCTO DE PRESTAMOS",
        "SUBPRODUCTO PRESTAMO",
        "FECHA DESEMBOLSO",
        "ESTATUS DEL CREDITO",
        "SALDO CAP",
        "SALDO INTERESES",
        "SALDO REAL EXIGIBLE",
        "DIAS MORA",
        "CARTERA EN RIESGO"
    }),

    ResultadoFinal = #"Columnas Reordenadas (detalle)"
in
    ResultadoFinal

let
    // Repoperativo_Transformado (revisión: JOIN sigue siendo Inner; normalización de REGION aplicada)
    rutaBase = "C:\Users\omjac\Documents\OMAR\ITTIVA\PROYECTOS 2025\MIGRACION TUIIO\repoperativo",
    rutaOficinas = rutaBase & "\Oficinas-Zona-Region.csv",

    TrimColumnName = (n as text) as text => Text.Trim(n),

    // Fuente unificada
    SourceRep = Repoperativo_Source,

    // Tipado limitado sobre las columnas que usaremos
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
            {"DIAS MORA", Int64.Type},
            {"CARTERA EN RIESGO", type number},
            {"FILE PATHS", type text},
            {"FECHA DE COSECHA", type text}
        }
    ),

    // Crear clave normalizada en la tabla principal (Trim + Upper) para matching más robusto
    SourceWithKey = Table.AddColumn(
        #"Tipo cambiado limitado",
        "__REGION_KEY__",
        each if Record.HasFields(_, "REGION") and _[REGION] <> null
             then Text.Trim(Text.Upper(Text.From(_[REGION])))
             else null,
        type text
    ),

    // Cargar oficinas desde la consulta preparada si existe, si no usar fallback (sin filtrar si proviene de Oficinas_Source)
    OficTry = try Oficinas_Source otherwise null,
    OficFinal =
        if OficTry <> null then
            Table.Buffer(OficTry)
        else
            let
                OrigenOficinas = Csv.Document(File.Contents(rutaOficinas), [Delimiter = ",", Encoding = 1252, QuoteStyle = QuoteStyle.None]),
                #"Encabezados Oficinas" = Table.PromoteHeaders(OrigenOficinas, [PromoteAllScalars = true]),
                #"Tipo Cambiado Oficinas" = Table.TransformColumnTypes(#"Encabezados Oficinas", {{"REGION", type text}, {"ZONA", type text}}),
                // Mantengo aquí el filtro que excluye "Centralizadora" tal como lo tenías en el fallback
                #"Filas Filtradas Oficinas" = Table.SelectRows(#"Tipo Cambiado Oficinas", each ([REGION] <> "Centralizadora" and [REGION] <> null and Text.Trim([REGION]) <> "")),
                OficinasUnicas = Table.Distinct(#"Filas Filtradas Oficinas", {"REGION"})
            in
                Table.Buffer(OficinasUnicas),

    // Añadir la misma clave normalizada a Oficinas para el join
    OficWithKey = Table.AddColumn(
        OficFinal,
        "__REGION_KEY__",
        each if Record.HasFields(_, "REGION") and [REGION] <> null
             then Text.Trim(Text.Upper(Text.From([REGION])))
             else null,
        type text
    ),

    OficBuffer = Table.Buffer(OficWithKey),

    // JOIN por la clave normalizada - JoinKind.Inner (conservar comportamiento de eliminar filas sin match en Oficinas)
    #"Combinar Consultas" = Table.NestedJoin(
        SourceWithKey, {"__REGION_KEY__"},
        OficBuffer, {"__REGION_KEY__"},
        "DataOficinas",
        JoinKind.Inner
    ),

    // Expandir ZONA desde las oficinas
    #"Expandir DataOficinas (zona)" = Table.ExpandTableColumn(#"Combinar Consultas", "DataOficinas", {"ZONA"}, {"ZONA"}),

    // Quitar columna auxiliar de clave para no dejarla en resultados
    #"Quitar Clave Auxiliar" = Table.RemoveColumns(#"Expandir DataOficinas (zona)", {"__REGION_KEY__"}),

    // Selección temprana de columnas necesarias
    #"Columnas Necesarias Seleccionadas" = Table.SelectColumns(#"Quitar Clave Auxiliar", {
        "FECHA DE COSECHA", "OFICINA", "REGION", "ZONA", "CONTRATO",
        "NOMBRE DEL ASESOR", "PRODUCTO DE PRESTAMOS", "SUBPRODUCTO PRESTAMO",
        "FECHA DESEMBOLSO", "ESTATUS DEL CREDITO", "SALDO CAP", "SALDO INTERESES",
        "SALDO REAL EXIGIBLE", "DIAS MORA", "CARTERA EN RIESGO"
    }),

    // Normalizar nombres de encabezado
    #"Nombres Recortados" = Table.TransformColumnNames(#"Columnas Necesarias Seleccionadas", each TrimColumnName(_)),

    // Eliminar duplicados previos al agrupado (como lo tenías). Si prefieres eliminarlo o deduplicar solo por clave, cámbialo aquí.
    #"Filas Unicas Previas" = Table.Distinct(#"Nombres Recortados"),

    // Agrupado por ZONA, REGION, OFICINA con sumas/primeros valores y DIAS MORA como lista
    #"Agrupado_Zona_Region_Oficina" = Table.Group(
        #"Filas Unicas Previas",
        {"ZONA", "REGION", "OFICINA"},
        {
            {"FECHA DE COSECHA", each let vals = List.RemoveNulls(_["FECHA DE COSECHA"]) in if List.Count(vals)=0 then null else List.First(vals), type nullable text},
            {"CONTRATO", each let v = List.RemoveNulls(_["CONTRATO"]) in if List.Count(v)=0 then null else List.First(v), Int64.Type},
            {"NOMBRE DEL ASESOR", each let v = List.RemoveNulls(_["NOMBRE DEL ASESOR"]) in if List.Count(v)=0 then null else List.First(v), type nullable text},
            {"PRODUCTO DE PRESTAMOS", each let v = List.RemoveNulls(_["PRODUCTO DE PRESTAMOS"]) in if List.Count(v)=0 then null else List.First(v), type nullable text},
            {"SUBPRODUCTO PRESTAMO", each let v = List.RemoveNulls(_["SUBPRODUCTO PRESTAMO"]) in if List.Count(v)=0 then null else List.First(v), type nullable text},
            {"FECHA DESEMBOLSO", each let v = List.RemoveNulls(_["FECHA DESEMBOLSO"]) in if List.Count(v)=0 then null else List.Min(v), type nullable date},
            {"ESTATUS DEL CREDITO", each let v = List.RemoveNulls(_["ESTATUS DEL CREDITO"]) in if List.Count(v)=0 then null else List.First(v), type nullable text},
            {"SALDO CAP", each List.Sum(List.RemoveNulls(_["SALDO CAP"])), type nullable number},
            {"SALDO INTERESES", each List.Sum(List.RemoveNulls(_["SALDO INTERESES"])), type nullable number},
            {"SALDO REAL EXIGIBLE", each List.Sum(List.RemoveNulls(_["SALDO REAL EXIGIBLE"])), type nullable number},
            {"DIAS MORA", each List.RemoveNulls(_["DIAS MORA"), type list},
            {"CARTERA EN RIESGO", each List.Sum(List.RemoveNulls(_["CARTERA EN RIESGO"])), type nullable number}
        }
    ),

    // Bufferizar el agrupado
    AgrupadoBuffer = Table.Buffer(#"Agrupado_Zona_Region_Oficina"),

    // Reordenar columnas
    #"Columnas Reordenadas (agrupado)" = Table.ReorderColumns(AgrupadoBuffer, {
        "FECHA DE COSECHA",
        "OFICINA",
        "REGION",
        "CONTRATO",
        "NOMBRE DEL ASESOR",
        "PRODUCTO DE PRESTAMOS",
        "SUBPRODUCTO PRESTAMO",
        "FECHA DESEMBOLSO",
        "ESTATUS DEL CREDITO",
        "SALDO CAP",
        "SALDO INTERESES",
        "SALDO REAL EXIGIBLE",
        "DIAS MORA",
        "CARTERA EN RIESGO",
        "ZONA"
    }),

    // Expandir DIAS MORA a filas
    #"DIAS MORA Expandidos" = Table.ExpandListColumn(#"Columnas Reordenadas (agrupado)", "DIAS MORA"),
    #"DIAS MORA Tipo" = Table.TransformColumnTypes(#"DIAS MORA Expandidos", {{"DIAS MORA", Int64.Type}}),

    ResultadoFinal = #"DIAS MORA Tipo"
in
    ResultadoFinal

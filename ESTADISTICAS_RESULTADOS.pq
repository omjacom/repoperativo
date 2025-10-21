let
    // Estadisticas_Resultados (corregida: CountNoMatch y CountCentralizadora añadidos)
    FilesList = try List.Distinct(Table.Column(Repoperativo_Source, "FILE PATHS")) otherwise {},
    FilesProcessedCount = try List.Count(FilesList) otherwise null,

    RepoperativoRowCount = try Table.RowCount(Repoperativo_Source) otherwise null,
    RepoperativoDistinctRowCount = try Table.RowCount(Table.Distinct(Repoperativo_Source)) otherwise null,

    OficinasRawCount = try Table.RowCount(Oficinas_Raw) otherwise null,
    OficinasFilteredCount = try Table.RowCount(Oficinas_Source) otherwise null,

    FinalResultCount =
        try
            let
                agrup = Repoperativo_Agrupado,
                diasLists = try Table.Column(agrup, "DIAS MORA") otherwise {},
                counts = List.Transform(diasLists, each if _ = null then 0 else List.Count(_)),
                total = List.Sum(counts)
            in
                total
        otherwise try Table.RowCount(Repoperativo_Transformado) otherwise null,

    // ---- Conteo de filas del origen sin match en Oficinas (arreglado y robusto) ----
    CountNoMatch =
        try
            let
                src = Repoperativo_Source,
                srcWithKey = Table.AddColumn(
                    src,
                    "__REGION_KEY__",
                    each if Record.HasFields(_, "REGION") and _[REGION] <> null
                         then Text.Trim(Text.Upper(Text.From(_[REGION])))
                         else null,
                    type text
                ),

                oficSrc = try Oficinas_Source otherwise null,
                oficWithKey =
                    if oficSrc = null then
                        #table({"__REGION_KEY__"}, {})
                    else
                        Table.AddColumn(
                            Table.TransformColumnTypes(oficSrc, {{"REGION", type text}}),
                            "__REGION_KEY__",
                            each if [REGION] = null then null else Text.Trim(Text.Upper(Text.From([REGION]))),
                            type text
                        ),

                joined = Table.NestedJoin(srcWithKey, {"__REGION_KEY__"}, Table.Buffer(oficWithKey), {"__REGION_KEY__"}, "t", JoinKind.LeftOuter),
                noMatch = Table.SelectRows(joined, each Table.RowCount([t]) = 0),
                totalNoMatch = Table.RowCount(noMatch)
            in
                totalNoMatch
        otherwise null,

    CountCentralizadora = try Table.RowCount(Table.SelectRows(Repoperativo_Source, each (if Record.HasFields(_, "REGION") and _[REGION] <> null then Text.Trim(Text.Upper(Text.From(_[REGION]))) else null) = "CENTRALIZADORA")) otherwise null,

    GeneratedAt = DateTime.ToText(DateTime.LocalNow(), "yyyy-MM-dd HH:mm:ss"),

    MetricsList = {
        [Metric = "Generado en", Value = GeneratedAt],
        [Metric = "Repoperativo - archivos procesados", Value = FilesProcessedCount],
        [Metric = "Repoperativo - filas totales (unificado)", Value = RepoperativoRowCount],
        [Metric = "Repoperativo - filas distintas (unificado)", Value = RepoperativoDistinctRowCount],
        [Metric = "Oficinas - filas origen (raw)", Value = OficinasRawCount],
        [Metric = "Oficinas - filas después de filtro (source)", Value = OficinasFilteredCount],
        [Metric = "Repoperativo - filas sin match en Oficinas (perdidas)", Value = CountNoMatch],
        [Metric = "Repoperativo - filas con REGION = CENTRALIZADORA", Value = CountCentralizadora],
        [Metric = "Resultado - filas finales (transformado)", Value = FinalResultCount]
    },

    MetricsTable = Table.FromRecords(MetricsList)
in
    MetricsTable

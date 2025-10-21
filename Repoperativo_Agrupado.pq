let
    // Repoperativo_Agrupado (robusta): obtiene la tabla agrupada (DIAS MORA como listas)
    SourceRepTry = try Repoperativo_Source otherwise null,
    OficTry = try Oficinas_Source otherwise try Oficinas_Raw otherwise null,

    inputCols = {
        "FECHA DE COSECHA","OFICINA","REGION","CONTRATO",
        "NOMBRE DEL ASESOR","PRODUCTO DE PRESTAMOS","SUBPRODUCTO PRESTAMO",
        "FECHA DESEMBOLSO","ESTATUS DEL CREDITO",
        "SALDO CAP","SALDO INTERESES","SALDO REAL EXIGIBLE",
        "DIAS MORA","CARTERA EN RIESGO"
    },

    EmptyTable = #table(
        {"ZONA","REGION","OFICINA"} & inputCols,
        {}
    ),

    SourceRep = if SourceRepTry = null then null else SourceRepTry,
    Ofic = if OficTry = null then null else OficTry,
    ResultEarlyExit = if (SourceRep = null) or (Table.IsEmpty(SourceRep)) then EmptyTable else null,
    _exit = if ResultEarlyExit <> null then ResultEarlyExit else null,

    EnsureColumn = (tbl as table, colName as text) as table =>
        if List.Contains(Table.ColumnNames(tbl), colName) then tbl
        else Table.AddColumn(tbl, colName, each null),

    SourceEnsured = List.Accumulate(inputCols, SourceRep, (state, current) => EnsureColumn(state, current)),

    SourceNorm = Table.TransformColumnNames(SourceEnsured, each Text.Trim(_)),

    SourceTyped = Table.TransformColumnTypes(SourceNorm, {
        {"OFICINA", type text}, {"REGION", type text}, {"CONTRATO", Int64.Type},
        {"NOMBRE DEL ASESOR", type text}, {"PRODUCTO DE PRESTAMOS", type text}, {"SUBPRODUCTO PRESTAMO", type text},
        {"FECHA DESEMBOLSO", type date}, {"ESTATUS DEL CREDITO", type text},
        {"SALDO CAP", type number}, {"SALDO INTERESES", type number}, {"SALDO REAL EXIGIBLE", type number},
        {"DIAS MORA", Int64.Type}, {"CARTERA EN RIESGO", type number}, {"FECHA DE COSECHA", type text}
    }),

    OficFinal =
        if Ofic = null then
            #table({"REGION","ZONA"}, {})
        else
            Table.Buffer(Ofic),

    Joined = Table.NestedJoin(SourceTyped, {"REGION"}, OficFinal, {"REGION"}, "DataOficinas", JoinKind.LeftOuter),
    WithZona = Table.ExpandTableColumn(Joined, "DataOficinas", {"ZONA"}, {"ZONA"}),

    Selected = Table.SelectColumns(WithZona, List.Distinct({"ZONA","REGION","OFICINA"} & inputCols)),

    RemoveHeaderLikeRows = Table.SelectRows(Selected, each
        List.AnyTrue(List.Transform(Table.ColumnNames(Selected), (c) =>
            let v = Record.Field(_, c) in Text.Trim(Text.From(if v = null then "" else v)) <> Text.Trim(c)
        ))
    ),

    UniqueRows = Table.Distinct(RemoveHeaderLikeRows),

    Agrupado = Table.Group(
        UniqueRows,
        {"ZONA","REGION","OFICINA"},
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
            {"DIAS MORA", each let l = List.RemoveNulls(_["DIAS MORA"]) in if List.Count(l)=0 then {} else l, type list},
            {"CARTERA EN RIESGO", each List.Sum(List.RemoveNulls(_["CARTERA EN RIESGO"])), type nullable number}
        }
    ),

    AgrupadoBuffer = Table.Buffer(Agrupado)
in
    if _exit <> null then _exit else AgrupadoBuffer

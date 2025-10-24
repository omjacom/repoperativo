let
    // Oficinas_Source: normaliza REGION (mayúsculas, sin tildes, trim extremos)
    // y luego agrupa para devolver UNA fila por REGION (ZONA = primer valor no-nulo por region)

    SourceRaw = try Oficinas_Raw otherwise null,
    SourceInitial =
        if SourceRaw <> null then
            SourceRaw
        else
            #table({"REGION","ZONA"}, {}),

    // Asegurar existencia de columna REGION y ZONA
    SourceEnsured =
        let base = SourceInitial
        in
            if List.Contains(Table.ColumnNames(base), "REGION") and List.Contains(Table.ColumnNames(base), "ZONA") then
                base
            else if List.Contains(Table.ColumnNames(base), "REGION") then
                Table.AddColumn(base, "ZONA", each null, type text)
            else if List.Contains(Table.ColumnNames(base), "ZONA") then
                Table.AddColumn(base, "REGION", each null, type text)
            else
                Table.AddColumn(Table.AddColumn(base, "REGION", each null, type text), "ZONA", each null, type text),

    // Función para eliminar tildes y normalizar ñ -> n
    RemoveDiacritics = (txt as nullable text) as nullable text =>
        let
            s0 = if txt = null then null else Text.From(txt),
            s1 = if s0 = null then null else Text.Replace(s0, "á", "a"),
            s2 = if s1 = null then null else Text.Replace(s1, "Á", "A"),
            s3 = if s2 = null then null else Text.Replace(s2, "é", "e"),
            s4 = if s3 = null then null else Text.Replace(s3, "É", "E"),
            s5 = if s4 = null then null else Text.Replace(s4, "í", "i"),
            s6 = if s5 = null then null else Text.Replace(s5, "Í", "I"),
            s7 = if s6 = null then null else Text.Replace(s6, "ó", "o"),
            s8 = if s7 = null then null else Text.Replace(s7, "Ó", "O"),
            s9 = if s8 = null then null else Text.Replace(s8, "ú", "u"),
            s10 = if s9 = null then null else Text.Replace(s9, "Ú", "U"),
            s11 = if s10 = null then null else Text.Replace(s10, "ñ", "n"),
            s12 = if s11 = null then null else Text.Replace(s11, "Ñ", "N")
        in
            s12,

    // Normalización solicitada: reemplazar NBSP/ZWSP, quitar tildes/ñ, trim extremos, y pasar a mayúsculas.
    // Nota: no se tocan espacios intermedios.
    NormalizeRegion = (v as any) as nullable text =>
        let
            raw = if v = null then null else Text.From(v),
            noNbsp = if raw = null then null else Text.Replace(raw, Character.FromNumber(160), " "),
            noZwsp = if noNbsp = null then null else Text.Replace(noNbsp, Character.FromNumber(8203), ""),
            noDiacritics = if noZwsp = null then null else RemoveDiacritics(noZwsp),
            trimmed = if noDiacritics = null then null else Text.Trim(noDiacritics),
            uppered = if trimmed = null then null else Text.Upper(trimmed)
        in
            uppered,

    // Aplicar la normalización solo en la columna REGION (dejando ZONA tal cual)
    Oficinas_Normalized = Table.TransformColumns(SourceEnsured, {{"REGION", each NormalizeRegion(_), type text}}),

    // Agrupar para devolver UNA fila por REGION:
    // - si hay varias filas por REGION, tomar la primera ZONA no-nula encontrada
    Oficinas_Unicas = Table.Group(
        Oficinas_Normalized,
        {"REGION"},
        {
            {"ZONA", each
                let vals = List.RemoveNulls(Table.Column(_, "ZONA"))
                in if List.Count(vals)=0 then null else List.First(vals), type nullable text},
            {"RowsCount", each Table.RowCount(_), Int64.Type}
        }
    ),

    // (opcional) quitar columna RowsCount si no es necesaria en salida final
    Oficinas_Result = Table.RemoveColumns(Oficinas_Unicas, {"RowsCount"})
in
    Oficinas_Result
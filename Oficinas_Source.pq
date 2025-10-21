let
    // Oficinas_Source: limpieza y deduplicación de la tabla de oficinas (lista pequeña, bufferizada)
    SourceRaw = Oficinas_Raw, // requiere que exista la consulta Oficinas_Raw
    #"Filas Filtradas" = Table.SelectRows(SourceRaw, each ([REGION] <> null and Text.Trim([REGION]) <> "")),
    // En el pasado se filtró REGION = "Centralizadora"; aquí mantenemos la opción de dejarla fuera si lo deseas.
    #"Filas Filtradas 2" = Table.SelectRows(#"Filas Filtradas", each Text.Trim([REGION]) <> "Centralizadora"),
    #"Tipo Cambiado" = Table.TransformColumnTypes(#"Filas Filtradas 2", {{"REGION", type text}, {"ZONA", type text}}),
    OficinasUnicas = Table.Distinct(#"Tipo Cambiado", {"REGION"}),
    Buffered = Table.Buffer(OficinasUnicas)
in
    Buffered

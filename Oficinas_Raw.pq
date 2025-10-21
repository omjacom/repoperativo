let
    // Oficinas_Raw: lectura cruda del CSV de oficinas (sin filtros fuertes)
    rutaBase = "C:\Users\omjac\Documents\OMAR\ITTIVA\PROYECTOS 2025\MIGRACION TUIIO\repoperativo",
    rutaOficinas = rutaBase & "\Oficinas-Zona-Region.csv",

    Origen = Csv.Document(File.Contents(rutaOficinas), [Delimiter = ",", Encoding = 1252, QuoteStyle = QuoteStyle.None]),
    #"Encabezados Promovidos" = Table.PromoteHeaders(Origen, [PromoteAllScalars = true]),
    #"Tipo cambiado (raw)" = Table.TransformColumnTypes(#"Encabezados Promovidos", {{"REGION", type text}, {"ZONA", type text}})
in
    #"Tipo cambiado (raw)"

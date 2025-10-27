let
    // Repoperativo_Source
    // - Escanea la carpeta rutaBase
    // - Selecciona archivos cuyo nombre empiece por "repoperativo_" y terminen en ".txt"
    // - Lee cada archivo (tab-delimitado), promueve encabezados, elimina filas que sean encabezados repetidos y agrega FILE PATHS y FECHA DE COSECHA
    rutaBase = "C:\Users\omjac\Documents\OMAR\ITTIVA\PROYECTOS 2025\MIGRACION TUIIO\repoperativo",

    // Helper: lista de dígitos (para extracción de fecha)
    Digits = List.Transform({0..9}, each Number.ToText(_)),

    // Helper: extracción robusta de la fecha de cosecha desde el nombre del archivo
    GetHarvestDate = (fileName as text) as nullable text =>
        let
            parts = Text.Split(fileName, "_"),
            candidate = if List.Count(parts) >= 2 then parts{1} else "",
            candidateDigits = Text.Select(candidate, Digits),
            len = Text.Length(fileName),
            windowStartList = if len >= 8 then {0..(len - 8)} else {},
            windows = List.Transform(windowStartList, each Text.Range(fileName, _, 8)),
            found = List.First(List.Select(windows, each Text.Length(Text.Select(_, Digits)) = 8), null)
        in
            if Text.Length(candidateDigits) = 8 then candidateDigits else found,

    // Helper: elimina filas que coincidan exactamente con los nombres de columna (encabezado repetido)
    RemoveHeaderLikeRows = (tbl as table) as table =>
        let
            cols = Table.ColumnNames(tbl),
            // Filtrar filas que NO sean idénticas al encabezado (es decir: mantener filas donde al menos una columna difiere del nombre)
            filtered = Table.SelectRows(tbl, each List.AnyTrue(List.Transform(cols, (c) => 
                // convertir valor a texto para comparación segura (nulos -> "")
                let v = Record.Field(_, c) in Text.Trim(Text.From(if v = null then "" else v)) <> Text.Trim(c)
            )))
        in
            filtered,

    // Obtener lista de archivos en la carpeta
    AllFiles = Folder.Files(rutaBase),

    // Filtrar solo archivos cuyo prefijo en el nombre sea "repoperativo_" y que terminen en ".txt"
    // Usamos Text.Lower para evitar problemas con mayúsculas/minúsculas en la extensión o nombre.
    RepFiles = Table.SelectRows(
        AllFiles, 
        each
            let nm = Text.Lower( Text.Trim( Record.Field(_, "Name") ) ) in
            Text.StartsWith(nm, "repoperativo_") and Text.EndsWith(nm, ".txt")
    ),

    // Función que procesa un registro de Folder.Files y devuelve una tabla con encabezados promovidos y columna FILE PATHS
    ProcessFile = (fileRecord as record) as table =>
        let
            content = fileRecord[Content],
            // Leer CSV/TSV (tab delimited), promover encabezados (se asume que cada archivo trae encabezado)
            tblRaw = Csv.Document(content, [Delimiter = "#(tab)", Encoding = 1252, QuoteStyle = QuoteStyle.None]),
            promoted = Table.PromoteHeaders(tblRaw, [PromoteAllScalars = true]),
            // Normalizar nombres de columnas: recortar espacios al inicio/fin
            normalizedNames = Table.TransformColumnNames(promoted, each Text.Trim(_)),
            // Eliminar filas que vistas como encabezado repetido (por si algún archivo incluye la fila de header como dato)
            cleaned = RemoveHeaderLikeRows(normalizedNames),
            // Agregar columna FILE PATHS con el nombre del archivo
            withPath = Table.AddColumn(cleaned, "FILE PATHS", each fileRecord[Name], type text)
        in
            withPath,

    // Convertir la tabla de archivos a lista de records y procesar cada archivo
    RepFileRecords = Table.ToRecords(RepFiles),
    TablesList = List.Transform(RepFileRecords, each ProcessFile(_)),

    // Combinar todas las tablas (si no hay archivos, devolvemos tabla vacía con 0 columnas)
    Combined =
        if List.Count(TablesList) = 0
        then #table({}, {})
        else Table.Combine(TablesList),

    // Añadir FECHA DE COSECHA basada en FILE PATHS (columna en MAYÚSCULAS tal como pediste)
    #"Con Fecha de Cosecha" =
        if Table.IsEmpty(Combined)
        then Combined
        else Table.AddColumn(Combined, "FECHA DE COSECHA", each GetHarvestDate([FILE PATHS]), type text)
in
    #"Con Fecha de Cosecha"
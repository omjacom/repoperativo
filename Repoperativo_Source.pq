let
    // Repoperativo_Source: combina archivos CSV desde una carpeta, normaliza encabezados,
    // elimina filas de encabezado repetidas dentro de los CSV y añade FILE PATHS y FECHA DE COSECHA.
    RutaBase = "C:\Users\omjac\Documents\OMAR\ITTIVA\PROYECTOS 2025\MIGRACION TUIIO\repoperativo",
    Carpeta = RutaBase & "\data",

    // Listar archivos
    Files = Folder.Files(Carpeta),

    // Filtrar solo CSVs que interesan (opcional ajustar patrón)
    CsvFiles = Table.SelectRows(Files, each Text.EndsWith([Name], ".csv", Comparer.OrdinalIgnoreCase)),

    // Función para leer y normalizar un archivo CSV
    ReadCsv = (row as record) =>
        let
            content = Csv.Document(File.Contents(row[Folder Path] & row[Name]), [Delimiter = ",", Encoding = 1252, QuoteStyle = QuoteStyle.None]),
            promoted = Table.PromoteHeaders(content, [PromoteAllScalars = true]),
            // Eliminar filas que coincidan exactamente con encabezado repetido dentro del archivo
            cols = Table.ColumnNames(promoted),
            cleaned = Table.SelectRows(promoted, each List.AnyTrue(List.Transform(cols, (c) =>
                let v = Record.Field(_, c) in Text.Trim(Text.From(if v = null then "" else v)) <> Text.Trim(c)
            ))),
            // Añadir metadatos del archivo
            withMeta = Table.AddColumn(cleaned, "FILE PATHS", each row[Folder Path] & row[Name]),
            withFecha = Table.AddColumn(withMeta, "FECHA DE COSECHA", each DateTime.ToText(DateTime.LocalNow(), "yyyy-MM-dd"))
        in
            withFecha,

    // Leer todos los archivos y combinarlos
    ReadAll = Table.AddColumn(CsvFiles, "Data", each ReadCsv(_)),
    Expanded = Table.ExpandTableColumn(ReadAll, "Data", Table.ColumnNames( ReadCsv( Table.FirstValue(CsvFiles) ) ), Table.ColumnNames( ReadCsv( Table.FirstValue(CsvFiles) ) )),
    // Si los archivos tienen columnas distintas, promover un esquema consistente puede ser necesario.
    Result = Expanded
in
    Result

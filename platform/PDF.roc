interface PDF
    exposes [
        save,
    ]
    imports [Effect, InternalTask.{Task}]

save : Str -> Task {} [PDFSaveError Str]
save = \path ->
    Effect.save path
    |> Effect.map \result ->
        when result is 
            Ok {} -> Ok {}
            Err msg -> Err (PDFSaveError msg)
    |> InternalTask.fromEffect
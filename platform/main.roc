platform "roc-pdf-experiment"
    requires {} { main : Task {} _ }
    exposes [
        Things,
        Task,
    ]
    packages {}
    imports [Task.{Task}]
    provides [mainForHost]

mainForHost : Task {} I32
mainForHost =
    Task.attempt main \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code) -> Task.err code
            Err e -> crash (Inspect.toStr e)
    
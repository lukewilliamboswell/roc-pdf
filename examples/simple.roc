app "simple"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Task.{Task},
        pf.PDF,
    ]
    provides [main] to pf

main : Task {} _
main = 

    # let's just save the default pdf
    PDF.save "test.pdf"
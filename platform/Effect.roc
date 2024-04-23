hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,

        # platform effects
        save,
    ]
    imports []
    generates Effect with [after, map, always, forever, loop]

save : Str -> Effect (Result {} Str)